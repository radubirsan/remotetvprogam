import Foundation

/// A single Samsung TV the app can talk to, identified by IP and connection mode.
struct TVDevice: Sendable, Hashable, Identifiable {
    var ip: String
    var name: String
    var mode: TVConnectionMode

    var id: String { "\(ip)|\(mode.rawValue)" }
}
