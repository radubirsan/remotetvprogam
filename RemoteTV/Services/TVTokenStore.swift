import Foundation

/// Persistence abstraction for pairing tokens returned by the TV on first successful connect.
/// Keyed by TV IP so each remembered TV has its own token.
protocol TVTokenStore: Sendable {
    func token(for ip: String) async -> String?
    func save(_ token: String, for ip: String) async throws
    func delete(for ip: String) async throws
}
