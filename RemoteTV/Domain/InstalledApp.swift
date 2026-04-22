import Foundation

/// A single app found installed on the TV (by REST-probing the IDs in ``KnownTVApps``).
/// Rendered as a button in ``InstalledAppsSection``; tapping launches the app by ``appID``.
struct InstalledApp: Sendable, Identifiable, Hashable, Codable {
    var appID: String
    var name: String

    var id: String { appID }
}
