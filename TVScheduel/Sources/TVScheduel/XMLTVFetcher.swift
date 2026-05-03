import Foundation
#if canImport(Compression)
import Compression
#endif

/// Downloads an XMLTV feed and caches the raw payload on disk so we don't re-fetch
/// within the cache TTL.
public actor XMLTVFetcher {

    public struct Configuration: Sendable {
        public var sourceURL: URL
        public var cacheDirectory: URL
        public var cacheTTL: TimeInterval
        public var requestTimeout: TimeInterval

        public init(
            sourceURL: URL,
            cacheDirectory: URL = .temporaryDirectory.appending(path: "tvepg-cache"),
            cacheTTL: TimeInterval = 24 * 60 * 60,
            requestTimeout: TimeInterval = 60
        ) {
            self.sourceURL = sourceURL
            self.cacheDirectory = cacheDirectory
            self.cacheTTL = cacheTTL
            self.requestTimeout = requestTimeout
        }
    }

    public enum FetchError: Error, CustomStringConvertible {
        case httpStatus(Int)
        case decompression
        case cacheUnreadable

        public var description: String {
            switch self {
            case .httpStatus(let code): "HTTP \(code) from XMLTV source"
            case .decompression: "Couldn't decompress gzipped XMLTV payload"
            case .cacheUnreadable: "Cached XMLTV file exists but couldn't be read"
            }
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Fetches the XMLTV document, returning the raw uncompressed XML bytes.
    /// Uses the on-disk cache when fresh; refetches when stale or absent.
    public func fetchRawXML(forceRefresh: Bool = false) async throws -> Data {
        let cacheURL = cacheFileURL()

        if !forceRefresh, let cached = try? readCachedIfFresh(at: cacheURL) {
            return cached
        }

        var request = URLRequest(url: configuration.sourceURL)
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }

        let xml = isGzipped(data) ? try gunzip(data) : data
        try writeCache(xml, to: cacheURL)
        return xml
    }

    /// Fetches and parses in one call.
    public func fetchGuide(forceRefresh: Bool = false) async throws -> Guide {
        let xml = try await fetchRawXML(forceRefresh: forceRefresh)
        return try XMLTVParser.parse(xml)
    }

    // MARK: - Cache

    private func cacheFileURL() -> URL {
        let safeHost = configuration.sourceURL.host ?? "source"
        let hashed = abs(configuration.sourceURL.absoluteString.hashValue)
        let name = "\(safeHost)-\(hashed).xml"
        return configuration.cacheDirectory.appending(path: name)
    }

    private func readCachedIfFresh(at url: URL) throws -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard let modified = attrs[.modificationDate] as? Date else { return nil }
        guard Date.now.timeIntervalSince(modified) < configuration.cacheTTL else { return nil }
        return try Data(contentsOf: url)
    }

    private func writeCache(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: configuration.cacheDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    // MARK: - gzip

    private func isGzipped(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b
    }

    /// Decompress a gzip stream using `Compression`.
    /// We strip the gzip header and CRC trailer and feed the raw deflate body to
    /// `compression_stream` with `COMPRESSION_ZLIB` (raw deflate).
    private func gunzip(_ data: Data) throws -> Data {
        // RFC 1952: 10-byte fixed header, optional fields, then deflate body, then 8-byte trailer.
        guard data.count > 18 else { throw FetchError.decompression }
        var offset = 10
        let flags = data[3]
        // FEXTRA
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { throw FetchError.decompression }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME (null-terminated)
        if flags & 0x08 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FCOMMENT (null-terminated)
        if flags & 0x10 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < data.count - 8 else { throw FetchError.decompression }

        let body = data.subdata(in: offset..<(data.count - 8))
        return try inflateDeflate(body)
    }

    private func inflateDeflate(_ data: Data) throws -> Data {
        #if !canImport(Compression)
        // Linux build (e.g. CI) — gzip handling needs Apple's Compression framework.
        // Pre-decompress the payload before feeding it to the fetcher.
        throw FetchError.decompression
        #else
        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }

        // Use the destination pointer as a harmless placeholder for src_ptr; we overwrite
        // it inside the withUnsafeBytes block before any process() call.
        streamPtr.initialize(to: compression_stream(
            dst_ptr: destination,
            dst_size: bufferSize,
            src_ptr: UnsafePointer(destination),
            src_size: 0,
            state: nil
        ))

        guard compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else {
            throw FetchError.decompression
        }
        defer { compression_stream_destroy(streamPtr) }

        var output = Data()
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            streamPtr.pointee.src_ptr = base
            streamPtr.pointee.src_size = data.count

            while true {
                streamPtr.pointee.dst_ptr = destination
                streamPtr.pointee.dst_size = bufferSize
                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - streamPtr.pointee.dst_size
                if produced > 0 {
                    output.append(destination, count: produced)
                }
                if status == COMPRESSION_STATUS_END { return }
                if status != COMPRESSION_STATUS_OK { throw FetchError.decompression }
            }
        }
        return output
        #endif
    }
}
