import SwiftUI

/// Which directional input is shown to the user inside ``RemoteView``: the classic
/// 5-button D-Pad (``DPadSection``) or a virtual trackpad surface (``TrackpadSection``)
/// that converts swipes into directional key presses and taps into `KEY_ENTER`.
///
/// `String`-backed so it can persist across launches via `@AppStorage`, matching the
/// existing `lastConnectionMode` pattern documented in the project README.
enum RemoteInputMode: String, CaseIterable, Identifiable {
    case dpad
    case trackpad

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .dpad: "D-Pad"
        case .trackpad: "Trackpad"
        }
    }
}
