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
    /// Closes the foreground app. Used as part of the ``RemoteViewModel/goLive`` sequence
    /// because `KEY_TV` alone is intercepted by Netflix/HBO/etc. and never reaches Tizen.
    case exit = "KEY_EXIT"
    case liveTV = "KEY_TV"
    case powerOff = "KEY_POWER"
    /// Single play/pause toggle on most Tizen builds — `KEY_PLAY` is the universally
    /// accepted code; some recent firmwares also accept `KEY_PAUSE` separately, but
    /// `KEY_PLAY` is the safer single-button mapping.
    case playPause = "KEY_PLAY"
    /// Closed-captions / audio-description toggle. Backs the "CC/AD" hint label in the
    /// remote UI.
    case captions = "KEY_CAPTION"

    var id: String { rawValue }
}
