import Foundation

/// Non-secret metadata persisted for a TV the user has paired with.
///
/// Keyed by IP in this POC iteration; `udn` is populated when Bonjour discovery carries it
/// in the TXT record, but remains optional so older records stay valid without a migration.
/// The auth token lives in the Keychain — this record only holds things that are safe to sit
/// in a JSON file.
struct RememberedTV: Sendable, Identifiable, Hashable, Codable {
    var id: String { ip }
    var ip: String
    var friendlyName: String
    var modelName: String
    var mac: String?
    var udn: String?
}
