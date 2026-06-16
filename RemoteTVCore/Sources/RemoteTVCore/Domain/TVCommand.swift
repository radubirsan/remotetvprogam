import Foundation

/// Samsung TV remote key codes sent over the WebSocket control channel.
public enum TVCommand: String, CaseIterable, Sendable, Identifiable {
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
    /// Plain power-button press — toggles the TV between awake and standby. Wired to
    /// a *short* tap on the on-screen power control; a long press fires
    /// ``sleepTimer`` instead so the user can reach the menu without juggling two
    /// separate buttons.
    case power = "KEY_POWER"
    /// Opens Tizen's Sleep Timer menu. Same hardware behaviour as long-pressing the
    /// physical remote's power button; surfaced as the long-press companion to
    /// ``power``.
    case sleepTimer = "KEY_SLEEP"
    /// Single play/pause toggle on most Tizen builds — `KEY_PLAY` is the universally
    /// accepted code; some recent firmwares also accept `KEY_PAUSE` separately, but
    /// `KEY_PLAY` is the safer single-button mapping.
    case playPause = "KEY_PLAY"
    /// Closed-captions / audio-description toggle. Backs the "CC/AD" hint label in the
    /// remote UI.
    case captions = "KEY_CAPTION"
    case digit0 = "KEY_0"
    case digit1 = "KEY_1"
    case digit2 = "KEY_2"
    case digit3 = "KEY_3"
    case digit4 = "KEY_4"
    case digit5 = "KEY_5"
    case digit6 = "KEY_6"
    case digit7 = "KEY_7"
    case digit8 = "KEY_8"
    case digit9 = "KEY_9"

    public var id: String { rawValue }

    /// Returns the matching `KEY_<n>` command for a single decimal digit. Used by the
    /// on-screen number pad to dispatch each tap without a switch ladder at the call
    /// site. Returns nil for out-of-range integers so callers fail closed.
    public static func digit(_ value: Int) -> TVCommand? {
        switch value {
        case 0: .digit0
        case 1: .digit1
        case 2: .digit2
        case 3: .digit3
        case 4: .digit4
        case 5: .digit5
        case 6: .digit6
        case 7: .digit7
        case 8: .digit8
        case 9: .digit9
        default: nil
        }
    }
}
