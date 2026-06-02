import Foundation

/// A single Samsung TV the app can talk to, identified by IP and connection mode.
///
/// `Codable` is used to round-trip the navigation path through `@AppStorage` so the
/// app can relaunch directly into the remote screen for the TV the user was last
/// controlling — the encoded fields are everything `RemoteView` needs to re-attempt a
/// connection on cold launch.
struct TVDevice: Sendable, Hashable, Identifiable, Codable {
    var ip: String
    var name: String
    var mode: TVConnectionMode
    /// The TV's Wi-Fi MAC, when known (captured on a prior connect and carried over
    /// from the remembered-TVs record). It's the only identifier that survives a DHCP
    /// IP rotation, so `SamsungTVService` uses it to find the pairing token under its
    /// MAC-keyed Keychain slot *without* a network probe — the difference between a
    /// silent reconnect and the TV re-prompting for pairing after a power cycle.
    ///
    /// Defaulted to `nil` (and decoded with `decodeIfPresent`) so devices persisted by
    /// older builds — and freshly discovered TVs we've never paired with — still decode.
    var mac: String? = nil

    /// Identity is intentionally `ip|mode` only — `mac` is supplementary data, not part
    /// of the device's identity, so learning the MAC later doesn't spawn a "new" device
    /// (which would, e.g., reset `RemoteView` via its `.id(device.id)`).
    var id: String { "\(ip)|\(mode.rawValue)" }
}
