import Foundation

/// Non-secret metadata persisted for a TV the user has paired with.
///
/// Keyed by IP in this POC iteration; `udn` is populated when Bonjour discovery carries it
/// in the TXT record, but remains optional so older records stay valid without a migration.
/// The auth token lives in the Keychain — this record only holds things that are safe to sit
/// in a JSON file.
public struct RememberedTV: Sendable, Identifiable, Hashable, Codable {
    public var id: String { ip }
    public var ip: String
    public var friendlyName: String
    public var modelName: String
    public var mac: String?
    public var udn: String?

    public init(ip: String, friendlyName: String, modelName: String, mac: String? = nil, udn: String? = nil) {
        self.ip = ip
        self.friendlyName = friendlyName
        self.modelName = modelName
        self.mac = mac
        self.udn = udn
    }
}
