import Foundation

/// A single app found installed on the TV (by REST-probing the IDs in ``KnownTVApps``).
/// Rendered as a button in ``InstalledAppsSection``; tapping launches the app by ``appID``.
public struct InstalledApp: Sendable, Identifiable, Hashable, Codable {
    public var appID: String
    public var name: String

    public var id: String { appID }

    public init(appID: String, name: String) {
        self.appID = appID
        self.name = name
    }
}
