import Foundation
import Testing
import RemoteTVCore
@testable import RemoteTV

private actor InMemoryTVTokenStore: TVTokenStore {
    private var storage: [String: String] = [:]

    func token(for ip: String) -> String? { storage[ip] }

    func save(_ token: String, for ip: String) throws {
        storage[ip] = token
    }

    func delete(for ip: String) throws {
        storage.removeValue(forKey: ip)
    }
}

struct TVTokenStoreTests {
    @Test func saveThenLoadRoundTrips() async throws {
        let store = InMemoryTVTokenStore()
        try await store.save("TOKEN-1", for: "192.168.1.42")
        let loaded = await store.token(for: "192.168.1.42")
        #expect(loaded == "TOKEN-1")
    }

    @Test func loadMissingReturnsNil() async {
        let store = InMemoryTVTokenStore()
        let loaded = await store.token(for: "10.0.0.1")
        #expect(loaded == nil)
    }

    @Test func deleteClearsToken() async throws {
        let store = InMemoryTVTokenStore()
        try await store.save("TOKEN-1", for: "192.168.1.42")
        try await store.delete(for: "192.168.1.42")
        let loaded = await store.token(for: "192.168.1.42")
        #expect(loaded == nil)
    }

    @Test func deleteMissingIsNoop() async throws {
        let store = InMemoryTVTokenStore()
        try await store.delete(for: "10.0.0.1")
    }

    @Test func saveOverwritesExistingToken() async throws {
        let store = InMemoryTVTokenStore()
        try await store.save("ORIGINAL", for: "192.168.1.42")
        try await store.save("REPLACEMENT", for: "192.168.1.42")
        let loaded = await store.token(for: "192.168.1.42")
        #expect(loaded == "REPLACEMENT")
    }

    @Test func tokensAreIsolatedPerIP() async throws {
        let store = InMemoryTVTokenStore()
        try await store.save("A", for: "192.168.1.1")
        try await store.save("B", for: "192.168.1.2")
        let a = await store.token(for: "192.168.1.1")
        let b = await store.token(for: "192.168.1.2")
        #expect(a == "A")
        #expect(b == "B")
    }
}
