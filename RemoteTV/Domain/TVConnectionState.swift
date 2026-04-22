import Foundation

/// Lifecycle of a Samsung TV websocket connection, as observed by the UI.
enum TVConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    /// Handshake opened; waiting for the user to approve pairing on the TV.
    case awaitingPairing
    case connected
    case failed(TVServiceError)
}
