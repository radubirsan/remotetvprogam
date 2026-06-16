import Foundation

/// Samsung Tizen app launcher identifiers for the streaming apps we surface as one-tap
/// shortcuts on the remote.
///
/// `appID` values are the modern Tizen (2019+) IDs the TV accepts through
/// `ms.channel.emit` / `ed.apps.launch`. Older models used different IDs; we don't
/// currently try to support them.
public enum TVApp: String, CaseIterable, Sendable, Identifiable, Hashable {
    case netflix
    case disneyPlus
    case youtube

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .netflix: "Netflix"
        case .disneyPlus: "Disney+"
        case .youtube: "YouTube"
        }
    }

    public var appID: String {
        switch self {
        case .netflix: "3201907018807"
        case .disneyPlus: "3201901017640"
        case .youtube: "111299001912"
        }
    }
}
