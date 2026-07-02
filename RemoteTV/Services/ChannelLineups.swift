import Foundation
import Observation

// MARK: - Model

/// The channel-number catalog published on the `lineup-data` branch by
/// `.github/workflows/lineups-update.yml` (scraped monthly from digi.ro/grila). Decoded from
/// `lineups.json`. See `tools/digi-lineup-scraper/`.
struct ChannelLineupCatalog: Decodable, Sendable {
    let schemaVersion: Int
    /// ISO-8601 timestamp string — kept as text to avoid coupling the decoder to a date format.
    let generatedAt: String
    var source: String?
    let lineups: [ChannelLineup]
}

/// One channel in a lineup. `guideID` is the matched EPG id (nil when the EPG feed doesn't
/// carry this channel — it still shows, just with no programme schedule). `logo` is the Digi
/// logo URL. `position` is the digital channel number.
struct LineupChannel: Decodable, Sendable, Hashable, Identifiable {
    let position: Int
    let name: String
    let logo: URL?
    let guideID: String?

    /// Stable id for SwiftUI + programme lookup: the EPG id when matched, else a synthetic
    /// position-based id (channels with no EPG match get an empty timeline).
    var id: String { guideID ?? "digi:\(position)" }
}

/// One provider/region/signal lineup: every digital channel (matched to EPG or not), each with
/// its position and logo. Positions genuinely differ by county (Cluj vs București), hence one
/// per county. Decodes schema v2 (`channels`) and tolerates the old v1 `numbers` map.
struct ChannelLineup: Decodable, Sendable, Identifiable, Hashable {
    let id: String          // e.g. "digi-cluj-digital"
    let provider: String    // "Digi"
    let region: String      // "Cluj"
    let regionCode: String  // "cluj"
    let type: String        // "digital"
    let channels: [LineupChannel]

    /// User-facing label for the picker, e.g. "Digi · Cluj".
    var displayName: String { "\(provider) · \(region)" }

    /// Matched channels only → `[guideID: position]`, for `KnownChannelNumbers`.
    var numbers: [String: Int] {
        Dictionary(
            channels.compactMap { c in c.guideID.map { ($0, c.position) } },
            uniquingKeysWith: { first, _ in first })
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, region, regionCode, type, channels, numbers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        provider = try c.decode(String.self, forKey: .provider)
        region = try c.decode(String.self, forKey: .region)
        regionCode = try c.decode(String.self, forKey: .regionCode)
        type = try c.decode(String.self, forKey: .type)
        if let v2 = try c.decodeIfPresent([LineupChannel].self, forKey: .channels) {
            channels = v2
        } else if let v1 = try c.decodeIfPresent([String: Int].self, forKey: .numbers) {
            // v1 fallback (stale cache): synthesize channels from the numbers map — no logos.
            channels = v1
                .map { LineupChannel(position: $0.value, name: KnownChannelNumbers.displayName(for: $0.key),
                                     logo: nil, guideID: $0.key) }
                .sorted { $0.position < $1.position }
        } else {
            channels = []
        }
    }
}

// MARK: - Client

/// Fetches `lineups.json` from the `lineup-data` branch and caches it. Mirrors ``EPGClient``:
/// in-memory + on-disk cache honouring a TTL (lineups change a few times a year, so the TTL is
/// long). When the feed is unavailable, callers fall back to ``KnownChannelNumbers/defaultMapping``.
actor LineupClient {

    struct Configuration: Sendable {
        var sourceURL: URL
        var cacheDirectory: URL
        var cacheTTL: TimeInterval
        var requestTimeout: TimeInterval

        init(
            sourceURL: URL = Configuration.defaultSourceURL,
            cacheDirectory: URL = URL.cachesDirectory.appending(path: "lineups"),
            cacheTTL: TimeInterval = 7 * 24 * 60 * 60,
            requestTimeout: TimeInterval = 60
        ) {
            self.sourceURL = sourceURL
            self.cacheDirectory = cacheDirectory
            self.cacheTTL = cacheTTL
            self.requestTimeout = requestTimeout
        }

        /// Raw URL of `lineups.json` on the orphan `lineup-data` branch of
        /// `radubirsan/remotetvprogam` (force-pushed monthly by the lineups workflow). If the
        /// repo owner/name changes, update this — same caveat as `EPGClient.defaultSourceURL`.
        static let defaultSourceURL = URL(
            string: "https://raw.githubusercontent.com/radubirsan/remotetvprogam/lineup-data/lineups.json"
        )!
    }

    /// Minimum acceptable `schemaVersion` — a cached catalog older than this is discarded and
    /// refetched (bump this whenever the schema changes shape).
    private static let minSchemaVersion = 2

    enum FetchError: Error, CustomStringConvertible {
        case httpStatus(Int)
        case decoding(any Error)

        var description: String {
            switch self {
            case .httpStatus(let code): "HTTP \(code) loading channel lineups"
            case .decoding(let error): "Lineup decode failed: \(error.localizedDescription)"
            }
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var inMemory: ChannelLineupCatalog?

    init(configuration: Configuration = .init(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Returns the cached catalog if fresh, otherwise downloads and decodes.
    func loadCatalog(forceRefresh: Bool = false) async throws -> ChannelLineupCatalog {
        if !forceRefresh, let inMemory { return inMemory }

        // Ignore a cache from an older schema (e.g. a v1 file cached before the v2 rollout) so a
        // schema bump isn't masked by the TTL — otherwise the app serves stale-shaped data (only
        // EPG-matched channels, no logos) for up to a week.
        let cacheURL = configuration.cacheDirectory.appending(path: "lineups.json")
        if !forceRefresh, let data = readCachedIfFresh(at: cacheURL),
           let catalog = try? decode(data), catalog.schemaVersion >= Self.minSchemaVersion {
            inMemory = catalog
            return catalog
        }

        var request = URLRequest(url: configuration.sourceURL)
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        let catalog = try decode(data)
        try? writeCache(data, to: cacheURL)
        inMemory = catalog
        return catalog
    }

    private func decode(_ data: Data) throws -> ChannelLineupCatalog {
        do { return try decoder.decode(ChannelLineupCatalog.self, from: data) }
        catch { throw FetchError.decoding(error) }
    }

    private func readCachedIfFresh(at url: URL) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) < configuration.cacheTTL else { return nil }
        return try? Data(contentsOf: url)
    }

    private func writeCache(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: configuration.cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Store

/// Owns the fetched catalog and the user's selected lineup, and pushes the selected lineup's
/// numbers into ``KnownChannelNumbers`` (which all tuning/EPG lookups read). `nil` selection
/// ⇒ the built-in default table. Held by ``RemoteView`` so the choice survives panel toggles.
@MainActor
@Observable
final class ChannelLineupStore {
    private let client: LineupClient
    private static let selectionKey = "selectedChannelLineupID"

    private(set) var catalog: ChannelLineupCatalog?
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// nil = "Built-in default" (compiled table). Persisted across launches.
    var selectedLineupID: String? {
        didSet {
            UserDefaults.standard.set(selectedLineupID, forKey: Self.selectionKey)
            applySelection()
        }
    }

    init(client: LineupClient = LineupClient()) {
        self.client = client
        self.selectedLineupID = UserDefaults.standard.string(forKey: Self.selectionKey)
    }

    /// Lineups sorted by region for the picker.
    var lineups: [ChannelLineup] {
        (catalog?.lineups ?? []).sorted { $0.region.localizedCompare($1.region) == .orderedAscending }
    }

    var selectedLineup: ChannelLineup? {
        guard let id = selectedLineupID else { return nil }
        return catalog?.lineups.first { $0.id == id }
    }

    /// Fetch the catalog (best-effort) and (re)apply the current selection. Safe to call on
    /// every appear — the client's caches make repeat calls cheap.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await client.loadCatalog()
            lastError = nil
        } catch {
            lastError = (error as? LineupClient.FetchError)?.description ?? error.localizedDescription
        }
        applySelection()
    }

    /// Push the selected lineup's numbers into the global lookup (or revert to default).
    private func applySelection() {
        KnownChannelNumbers.setActiveMapping(selectedLineup?.numbers)
    }
}
