import Foundation

/// Samsung TV remote key codes sent over the WebSocket control channel.
enum TVCommand: String, CaseIterable, Sendable, Identifiable {
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case enter = "KEY_ENTER"
    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case liveTV = "KEY_TV"
    case powerOff = "KEY_POWER"

    var id: String { rawValue }
}
