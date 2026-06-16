import Foundation

/// One entry in the on-device WebSocket sniff log. Surfaced in the remote UI so the user
/// can watch the Samsung control channel while poking the TV with the physical remote —
/// useful for fishing out Tizen app IDs that aren't in our static catalog.
public struct SniffLogEntry: Sendable, Identifiable, Hashable {
    public enum Direction: String, Sendable {
        case inbound
        case outbound
        case info
    }

    public let id: UUID
    public let timestamp: Date
    public let direction: Direction
    public let text: String

    public init(direction: Direction, text: String, timestamp: Date = .now) {
        self.id = UUID()
        self.timestamp = timestamp
        self.direction = direction
        self.text = text
    }
}
