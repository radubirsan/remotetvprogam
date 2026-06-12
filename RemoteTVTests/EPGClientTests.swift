import Foundation
import Testing
@testable import RemoteTV

/// Exercises ``EPGClient``'s three-layer caching (in-memory → disk → network) without
/// any real networking: the "network" source is a `file://` URL in a temp directory,
/// so deleting or rewriting that file simulates the remote changing or going away.
struct EPGClientTests {

    private func makeGuide(channelID: String = "Digi.24.HD.ro") -> EPGGuide {
        EPGGuide(
            channels: [EPGChannel(id: channelID, displayNames: ["Digi 24"], iconURL: nil)],
            programmes: [
                EPGProgramme(
                    channelID: channelID,
                    title: "Stiri",
                    subtitle: nil,
                    description: nil,
                    start: Date(timeIntervalSince1970: 1_700_000_000),
                    stop: Date(timeIntervalSince1970: 1_700_003_600),
                    categories: ["news"]
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Fresh temp dir + a `guide.json` "source" file the client downloads from.
    private func makeFixture(guide: EPGGuide) throws -> (sourceURL: URL, cacheDirectory: URL, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "epg-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appending(path: "source.json")
        try encode(guide).write(to: sourceURL)
        return (sourceURL, root.appending(path: "cache"), root)
    }

    private func encode(_ guide: EPGGuide) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601   // matches EPGClient's decoder
        return try encoder.encode(guide)
    }

    @Test func loadsAndDecodesFromSource() async throws {
        let fixture = try makeFixture(guide: makeGuide())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = EPGClient(configuration: .init(
            sourceURL: fixture.sourceURL, cacheDirectory: fixture.cacheDirectory
        ))

        let guide = try await client.loadGuide()

        #expect(guide.channels.map(\.id) == ["Digi.24.HD.ro"])
        #expect(guide.programmes.first?.title == "Stiri")
    }

    @Test func secondLoadServesInMemoryCacheWithoutTouchingSource() async throws {
        let fixture = try makeFixture(guide: makeGuide())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = EPGClient(configuration: .init(
            sourceURL: fixture.sourceURL, cacheDirectory: fixture.cacheDirectory
        ))
        _ = try await client.loadGuide()

        // Source gone — a second load must come from the in-memory copy.
        try FileManager.default.removeItem(at: fixture.sourceURL)
        let guide = try await client.loadGuide()

        #expect(guide.channels.count == 1)
    }

    @Test func freshDiskCacheServesNewClientWithoutSource() async throws {
        let fixture = try makeFixture(guide: makeGuide())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        // First client downloads and populates the disk cache.
        let first = EPGClient(configuration: .init(
            sourceURL: fixture.sourceURL, cacheDirectory: fixture.cacheDirectory
        ))
        _ = try await first.loadGuide()

        // Second client (fresh in-memory state) points at a dead source — the
        // still-fresh disk cache must carry it.
        let deadSource = fixture.root.appending(path: "missing.json")
        let second = EPGClient(configuration: .init(
            sourceURL: deadSource, cacheDirectory: fixture.cacheDirectory
        ))
        let guide = try await second.loadGuide()

        #expect(guide.channels.map(\.id) == ["Digi.24.HD.ro"])
    }

    @Test func forceRefreshBypassesBothCaches() async throws {
        let fixture = try makeFixture(guide: makeGuide())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let client = EPGClient(configuration: .init(
            sourceURL: fixture.sourceURL, cacheDirectory: fixture.cacheDirectory
        ))
        _ = try await client.loadGuide()

        // Both caches are warm, but forceRefresh must go back to the (now dead) source.
        try FileManager.default.removeItem(at: fixture.sourceURL)
        await #expect(throws: (any Error).self) {
            _ = try await client.loadGuide(forceRefresh: true)
        }
    }

    @Test func staleDiskCacheRefetchesFromSource() async throws {
        let fixture = try makeFixture(guide: makeGuide(channelID: "Old.Channel.ro"))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = EPGClient(configuration: .init(
            sourceURL: fixture.sourceURL, cacheDirectory: fixture.cacheDirectory
        ))
        _ = try await first.loadGuide()

        // Source now serves different content; a TTL of 0 makes the disk cache
        // always-stale, so a fresh client must re-download rather than serve it.
        try encode(makeGuide(channelID: "New.Channel.ro")).write(to: fixture.sourceURL)
        let second = EPGClient(configuration: .init(
            sourceURL: fixture.sourceURL, cacheDirectory: fixture.cacheDirectory, cacheTTL: 0
        ))
        let guide = try await second.loadGuide()

        #expect(guide.channels.map(\.id) == ["New.Channel.ro"])
    }
}
