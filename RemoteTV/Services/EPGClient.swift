import Foundation

/// Fetches the daily Romanian EPG JSON dump produced by the `epg-update`
/// GitHub Actions workflow and serves it back to view models.
///
/// The workflow lives at `.github/workflows/epg-update.yml`, runs `tvepg dump`
/// against the epgshare01 source, and force-pushes a single `guide.json` to the
/// `epg-data` branch. The default ``Configuration/sourceURL`` points at GitHub's
/// raw-content host for that branch — fill in the owner/repo placeholders before
/// shipping.
///
/// Caching strategy:
///   * In-memory cache for the lifetime of the actor — repeated `loadGuide()`
///     calls within a session decode at most once.
///   * On-disk cache in `URL.cachesDirectory.appending(path: "epg")`. iOS may
///     evict it under storage pressure, which is fine: we'll just re-download.
///   * Both caches honour ``Configuration/cacheTTL`` (24h by default).
actor EPGClient {

    struct Configuration: Sendable {
        var sourceURL: URL
        var cacheDirectory: URL
        var cacheTTL: TimeInterval
        var requestTimeout: TimeInterval

        init(
            sourceURL: URL,
            cacheDirectory: URL = URL.cachesDirectory.appending(path: "epg"),
            cacheTTL: TimeInterval = 24 * 60 * 60,
            requestTimeout: TimeInterval = 60
        ) {
            self.sourceURL = sourceURL
            self.cacheDirectory = cacheDirectory
            self.cacheTTL = cacheTTL
            self.requestTimeout = requestTimeout
        }

        /// Default URL of the JSON guide on GitHub raw. Produced daily by the
        /// `Update EPG` workflow in `.github/workflows/epg-update.yml`, which force-pushes
        /// to the orphan `epg-data` branch of `radubirsan/remotetvprogam`.
        ///
        /// Force-unwrapped — if this template ever fails to parse as a URL we want
        /// to crash loudly in development, not ship a half-working build.
        static let defaultSourceURL = URL(
            string: "https://raw.githubusercontent.com/radubirsan/remotetvprogam/epg-data/guide.json"
        )!
    }

    enum FetchError: Error, CustomStringConvertible {
        case httpStatus(Int)
        case decoding(any Error)

        var description: String {
            switch self {
            case .httpStatus(let code): "HTTP \(code) loading EPG guide"
            case .decoding(let error): "EPG decode failed: \(error.localizedDescription)"
            }
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let decoder: JSONDecoder
    private var inMemoryGuide: EPGGuide?

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Returns the cached guide if fresh, otherwise downloads and decodes.
    /// Subsequent calls within `cacheTTL` reuse the in-memory copy without I/O.
    func loadGuide(forceRefresh: Bool = false) async throws -> EPGGuide {
        if !forceRefresh, let guide = inMemoryGuide {
            return guide
        }

        let cacheURL = cacheFileURL()
        if !forceRefresh, let data = readCachedIfFresh(at: cacheURL) {
            let guide = try decode(data)
            inMemoryGuide = guide
            return guide
        }

        var request = URLRequest(url: configuration.sourceURL)
        request.timeoutInterval = configuration.requestTimeout
        // URLSession transparently handles Content-Encoding: gzip when offered, so
        // GitHub raw will deliver the JSON pre-compressed and we decode plain bytes.
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }

        let guide = try decode(data)
        try? writeCache(data, to: cacheURL)
        inMemoryGuide = guide
        return guide
    }

    /// Convenience: today's schedule for one channel id.
    func todaysSchedule(for channelID: String) async throws -> [EPGProgramme] {
        let guide = try await loadGuide()
        return guide.programmes(for: channelID, on: .now)
    }

    /// Convenience: what's airing right now on one channel id.
    func nowPlaying(on channelID: String, at date: Date = .now) async throws -> EPGProgramme? {
        let guide = try await loadGuide()
        return guide.nowPlaying(on: channelID, at: date)
    }

    // MARK: - Private

    private func decode(_ data: Data) throws -> EPGGuide {
        do {
            return try decoder.decode(EPGGuide.self, from: data)
        } catch {
            throw FetchError.decoding(error)
        }
    }

    private func cacheFileURL() -> URL {
        configuration.cacheDirectory.appending(path: "guide.json")
    }

    private func readCachedIfFresh(at url: URL) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) < configuration.cacheTTL else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func writeCache(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: configuration.cacheDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
