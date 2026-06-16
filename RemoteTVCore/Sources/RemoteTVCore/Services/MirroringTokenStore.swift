import Foundation

/// Fans token writes out to two stores and reads the primary first. The app uses this to
/// keep the Keychain as the authoritative token store while ALSO mirroring every token into
/// the App Group, where the Control Center extension's ``AppGroupTokenStore`` can read it.
///
/// This is what lets the extension authenticate (so Mute doesn't re-trigger the TV's pairing
/// popup) without sharing the Keychain across targets. Mirror failures are swallowed — the
/// primary is the source of truth; the mirror is a best-effort convenience copy.
public actor MirroringTokenStore: TVTokenStore {
    private let primary: any TVTokenStore
    private let mirror: any TVTokenStore

    public init(primary: any TVTokenStore, mirror: any TVTokenStore) {
        self.primary = primary
        self.mirror = mirror
    }

    public func token(for ip: String) async -> String? {
        if let token = await primary.token(for: ip) { return token }
        return await mirror.token(for: ip)
    }

    public func save(_ token: String, for ip: String) async throws {
        try await primary.save(token, for: ip)
        try? await mirror.save(token, for: ip)
    }

    public func delete(for ip: String) async throws {
        try await primary.delete(for: ip)
        try? await mirror.delete(for: ip)
    }
}
