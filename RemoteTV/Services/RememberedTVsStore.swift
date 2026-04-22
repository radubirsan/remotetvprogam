import Foundation

/// Non-secret metadata store for TVs the user has paired with. Token storage lives separately in
/// ``TVTokenStore``.
protocol RememberedTVsStore: Sendable {
    func all() async -> [RememberedTV]
    func get(ip: String) async -> RememberedTV?
    func upsert(_ tv: RememberedTV) async throws
    func delete(ip: String) async throws
}
