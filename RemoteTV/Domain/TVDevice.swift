import Foundation

/// A single Samsung TV the app can talk to, identified by IP and connection mode.
///
/// `Codable` is used to round-trip the navigation path through `@AppStorage` so the
/// app can relaunch directly into the remote screen for the TV the user was last
/// controlling — the encoded triple (`ip`, `name`, `mode`) is everything `RemoteView`
/// needs to re-attempt a connection on cold launch.
struct TVDevice: Sendable, Hashable, Identifiable, Codable {
    var ip: String
    var name: String
    var mode: TVConnectionMode

    var id: String { "\(ip)|\(mode.rawValue)" }
}
