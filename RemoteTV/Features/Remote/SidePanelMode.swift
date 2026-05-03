import SwiftUI

/// Which auxiliary panel is currently surfaced beside the remote in ``RemoteView``.
/// Mutually exclusive — opening one closes the other. Persisted via `@AppStorage` so
/// the user's last choice survives across launches, mirroring the project's
/// `lastConnectionMode` and `remoteInputMode` patterns.
enum SidePanelMode: String, CaseIterable, Identifiable {
    /// No panel; remote canvas takes the full window width.
    case none
    /// Hardcoded ``TVApp`` shortcut launcher, rendered to the *left* of the remote.
    /// Mutually exclusive with ``installedApps`` even though both share the left
    /// column — only one can be visible at a time.
    case shortcuts
    /// Installed-apps loader/list, rendered to the *left* of the remote.
    case installedApps
    /// WebSocket sniff log, rendered to the *right* of the remote.
    case sniffLog
    /// Romanian TV guide — channel list with current programme inline; tap a row for
    /// today's full schedule. Rendered to the *right* of the remote (mutually exclusive
    /// with ``sniffLog`` for that column).
    case tvGuide

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .none:           "Hidden"
        case .shortcuts:      "Shortcuts"
        case .installedApps:  "Installed Apps"
        case .sniffLog:       "Sniff Log"
        case .tvGuide:        "TV Guide"
        }
    }

    var systemImage: String {
        switch self {
        case .none:           "rectangle"
        case .shortcuts:      "star.fill"
        case .installedApps:  "square.grid.2x2"
        case .sniffLog:       "doc.text.magnifyingglass"
        case .tvGuide:        "tv"
        }
    }
}
