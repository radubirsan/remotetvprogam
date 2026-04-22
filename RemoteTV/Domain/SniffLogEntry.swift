import Foundation

/// One entry in the on-device WebSocket sniff log. Surfaced in the remote UI so the user
/// can watch the Samsung control channel while poking the TV with the physical remote —
/// useful for fishing out Tizen app IDs that aren't in our static catalog.
struct SniffLogEntry: Sendable, Identifiable, Hashable {
    enum Direction: String, Sendable {
        case inbound
        case outbound
        case info
    }

    let id: UUID
    let timestamp: Date
    let direction: Direction
    let text: String

    init(direction: Direction, text: String, timestamp: Date = .now) {
        self.id = UUID()
        self.timestamp = timestamp
        self.direction = direction
        self.text = text
    }
}
