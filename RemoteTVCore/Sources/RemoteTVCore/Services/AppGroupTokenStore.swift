import Foundation

/// ``TVTokenStore`` backed by the App Group `UserDefaults` suite, so the Control Center
/// widget extension (a separate process) can read the pairing token the app captured —
/// WITHOUT needing a shared Keychain access group. Only the App Group capability is
/// required, which the extension already relies on to read the active device.
///
/// The token only grants LAN remote control of the TV, so the App-Group container
/// (app-sandbox-private, file-data-protected) is an acceptable home for a copy of it. The
/// app keeps the Keychain copy as the authoritative store via ``MirroringTokenStore``.
public actor AppGroupTokenStore: TVTokenStore {
    private let defaults: UserDefaults
    private static let prefix = "tvtoken."

    public init(suiteName: String = SharedStorage.appGroupID) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func key(_ account: String) -> String { prefix + account }

    public func token(for ip: String) async -> String? {
        let value = defaults.string(forKey: Self.key(ip))
        return (value?.isEmpty == false) ? value : nil
    }

    public func save(_ token: String, for ip: String) async throws {
        guard !token.isEmpty else { return }
        defaults.set(token, forKey: Self.key(ip))
    }

    public func delete(for ip: String) async throws {
        defaults.removeObject(forKey: Self.key(ip))
    }
}
