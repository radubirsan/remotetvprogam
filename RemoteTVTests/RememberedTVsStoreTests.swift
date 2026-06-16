import Foundation
import Testing
import RemoteTVCore
@testable import RemoteTV

struct RememberedTVsStoreTests {
    @Test func roundTripsASingleRecord() async throws {
        let store = makeStore()
        let tv = RememberedTV(ip: "192.168.1.10", friendlyName: "Living Room", modelName: "UE50RU7105", mac: "AA:BB:CC:DD:EE:FF", udn: nil)

        try await store.upsert(tv)
        let loaded = await store.get(ip: "192.168.1.10")

        #expect(loaded == tv)
    }

    @Test func upsertReplacesSameIP() async throws {
        let store = makeStore()
        let first = RememberedTV(ip: "192.168.1.10", friendlyName: "Old", modelName: "X", mac: nil, udn: nil)
        let second = RememberedTV(ip: "192.168.1.10", friendlyName: "New", modelName: "X", mac: "AA:BB:CC:DD:EE:FF", udn: nil)

        try await store.upsert(first)
        try await store.upsert(second)
        let all = await store.all()

        #expect(all.count == 1)
        #expect(all.first?.friendlyName == "New")
        #expect(all.first?.mac == "AA:BB:CC:DD:EE:FF")
    }

    @Test func upsertPreservesPreviousMACWhenIncomingHasNone() async throws {
        let store = makeStore()
        let withMAC = RememberedTV(ip: "192.168.1.10", friendlyName: "Living Room", modelName: "X", mac: "AA:BB:CC:DD:EE:FF", udn: nil)
        let nameOnly = RememberedTV(ip: "192.168.1.10", friendlyName: "Living Room", modelName: "X", mac: nil, udn: nil)

        try await store.upsert(withMAC)
        try await store.upsert(nameOnly)

        let loaded = await store.get(ip: "192.168.1.10")
        #expect(loaded?.mac == "AA:BB:CC:DD:EE:FF", "Later upsert without MAC must not wipe the captured one")
    }

    @Test func deleteRemovesRecord() async throws {
        let store = makeStore()
        let tv = RememberedTV(ip: "192.168.1.10", friendlyName: "Living Room", modelName: "X", mac: nil, udn: nil)

        try await store.upsert(tv)
        try await store.delete(ip: "192.168.1.10")

        #expect(await store.get(ip: "192.168.1.10") == nil)
        #expect(await store.all().isEmpty)
    }

    @Test func allReturnsEmptyWhenNoFile() async throws {
        let store = makeStore()
        #expect(await store.all().isEmpty)
    }

    @Test func multipleRecordsCoexist() async throws {
        let store = makeStore()
        let a = RememberedTV(ip: "192.168.1.10", friendlyName: "Living", modelName: "A", mac: nil, udn: nil)
        let b = RememberedTV(ip: "192.168.1.11", friendlyName: "Bedroom", modelName: "B", mac: nil, udn: nil)

        try await store.upsert(a)
        try await store.upsert(b)

        let ips = await Set(store.all().map(\.ip))
        #expect(ips == ["192.168.1.10", "192.168.1.11"])
    }

    // MARK: - Helpers

    private func makeStore() -> FileRememberedTVsStore {
        let url = URL.temporaryDirectory.appending(path: "remembered-tvs-tests-\(UUID().uuidString).json")
        return FileRememberedTVsStore(url: url)
    }
}
