import Foundation
import Testing
@testable import RemoteTV

/// Sample v2 catalog: Cluj has an unmatched channel (guideID null) and logos; București shares
/// one channel at a different position.
private let sampleLineupsJSON = """
{"schemaVersion":2,"generatedAt":"2026-07-02T00:00:00Z","source":"test","lineups":[
  {"id":"digi-cluj-digital","provider":"Digi","region":"Cluj","regionCode":"cluj","type":"digital","channels":[
    {"position":7,"name":"Digi 24 HD","logo":"https://s.digi.ro/a.png","guideID":"Digi.24.HD.ro"},
    {"position":3,"name":"Pro TV HD","logo":"https://s.digi.ro/b.png","guideID":"PRO.TV.HD.ro"},
    {"position":99,"name":"Sport Extra HD","logo":"https://s.digi.ro/c.png","guideID":null}
  ]},
  {"id":"digi-bucuresti-digital","provider":"Digi","region":"București","regionCode":"bucuresti","type":"digital","channels":[
    {"position":59,"name":"Digi 24 HD","logo":null,"guideID":"Digi.24.HD.ro"}
  ]}
]}
"""

/// Pure decode/client/view-model tests — no global state, safe to run in parallel.
struct ChannelLineupDecodingTests {
    @Test func catalogDecodesV2() throws {
        let cat = try JSONDecoder().decode(ChannelLineupCatalog.self, from: Data(sampleLineupsJSON.utf8))
        #expect(cat.schemaVersion == 2)
        #expect(cat.lineups.count == 2)
        let cluj = try #require(cat.lineups.first { $0.id == "digi-cluj-digital" })
        #expect(cluj.displayName == "Digi · Cluj")
        #expect(cluj.channels.count == 3) // includes the unmatched one

        let matched = try #require(cluj.channels.first { $0.guideID == "Digi.24.HD.ro" })
        #expect(matched.position == 7)
        #expect(matched.logo?.absoluteString == "https://s.digi.ro/a.png")
        #expect(matched.id == "Digi.24.HD.ro")

        let unmatched = try #require(cluj.channels.first { $0.guideID == nil })
        #expect(unmatched.name == "Sport Extra HD")
        #expect(unmatched.id == "digi:99") // synthetic id for a channel with no EPG match

        // Computed `numbers` (for KnownChannelNumbers) includes only matched channels.
        #expect(cluj.numbers == ["Digi.24.HD.ro": 7, "PRO.TV.HD.ro": 3])
    }

    @Test func decodesLegacyV1NumbersMap() throws {
        let v1 = """
        {"schemaVersion":1,"generatedAt":"x","lineups":[
          {"id":"l","provider":"Digi","region":"R","regionCode":"r","type":"digital","numbers":{"Digi.24.HD.ro":59}}]}
        """
        let cat = try JSONDecoder().decode(ChannelLineupCatalog.self, from: Data(v1.utf8))
        #expect(cat.lineups[0].numbers == ["Digi.24.HD.ro": 59])
        #expect(cat.lineups[0].channels.first?.guideID == "Digi.24.HD.ro")
    }

    @Test func clientLoadsFromFileSource() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lineup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appending(path: "lineups.json")
        try sampleLineupsJSON.write(to: src, atomically: true, encoding: .utf8)

        let client = LineupClient(configuration: .init(
            sourceURL: src, cacheDirectory: dir.appending(path: "cache"), cacheTTL: 0))
        let cat = try await client.loadCatalog()
        #expect(cat.lineups.count == 2)
    }

    @MainActor
    @Test func epgViewModelListsAllLineupChannelsIncludingUnmatched() throws {
        let cat = try JSONDecoder().decode(ChannelLineupCatalog.self, from: Data(sampleLineupsJSON.utf8))
        let cluj = try #require(cat.lineups.first { $0.regionCode == "cluj" })
        let vm = EPGViewModel()
        vm.lineup = cluj

        #expect(vm.filteredChannels.count == 3) // all 3, incl. the EPG-unmatched channel
        let ids = vm.filteredChannels.map(\.id)
        #expect(ids.contains("digi:99"))
        // Tunable by position whether matched or not.
        #expect(vm.tvChannelNumber(for: "Digi.24.HD.ro") == 7)
        #expect(vm.tvChannelNumber(for: "digi:99") == 99)
        // Logo flows through as the channel's iconURL (drives the guide's logo cell).
        let matched = try #require(vm.filteredChannels.first { $0.id == "Digi.24.HD.ro" })
        #expect(matched.iconURL?.absoluteString == "https://s.digi.ro/a.png")
    }
}

/// Tests that mutate the global ``KnownChannelNumbers`` override. Serialized so they don't race
/// each other, and each restores the default (other suites read `KnownChannelNumbers`).
@Suite(.serialized)
struct KnownChannelNumbersOverrideTests {
    @Test func overrideReplacesLookupsAndReverts() {
        defer { KnownChannelNumbers.setActiveMapping(nil) }
        let defaultNumber = KnownChannelNumbers.defaultMapping["Digi.24.HD.ro"]

        KnownChannelNumbers.setActiveMapping(["Digi.24.HD.ro": 7, "PRO.TV.HD.ro": 3])
        #expect(KnownChannelNumbers.number(for: "Digi.24.HD.ro") == 7)
        #expect(KnownChannelNumbers.channelID(forNumber: 7) == "Digi.24.HD.ro")
        #expect(Set(KnownChannelNumbers.orderedIDs) == ["Digi.24.HD.ro", "PRO.TV.HD.ro"])

        KnownChannelNumbers.setActiveMapping(nil)
        #expect(KnownChannelNumbers.number(for: "Digi.24.HD.ro") == defaultNumber)
    }

    @Test func emptyOverrideFallsBackToDefault() {
        defer { KnownChannelNumbers.setActiveMapping(nil) }
        KnownChannelNumbers.setActiveMapping([:])
        #expect(KnownChannelNumbers.number(for: "Digi.24.HD.ro")
                == KnownChannelNumbers.defaultMapping["Digi.24.HD.ro"])
    }

    @MainActor
    @Test func storeAppliesSelectedLineupToGlobal() async throws {
        defer { KnownChannelNumbers.setActiveMapping(nil) }
        let dir = FileManager.default.temporaryDirectory.appending(path: "lineup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appending(path: "lineups.json")
        try sampleLineupsJSON.write(to: src, atomically: true, encoding: .utf8)

        let client = LineupClient(configuration: .init(
            sourceURL: src, cacheDirectory: dir.appending(path: "cache"), cacheTTL: 0))
        let store = ChannelLineupStore(client: client)
        store.selectedLineupID = nil
        await store.load()
        #expect(store.lineups.count == 2)

        store.selectedLineupID = "digi-cluj-digital"
        #expect(store.selectedLineup?.region == "Cluj")
        #expect(KnownChannelNumbers.number(for: "Digi.24.HD.ro") == 7) // matched-only numbers applied

        store.selectedLineupID = nil
        #expect(KnownChannelNumbers.number(for: "Digi.24.HD.ro")
                == KnownChannelNumbers.defaultMapping["Digi.24.HD.ro"])
    }
}
