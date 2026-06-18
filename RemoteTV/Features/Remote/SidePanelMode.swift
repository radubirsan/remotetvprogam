import RemoteTVCore
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

    var id: String { rawValue }

    /// Panels offered in the side-panel menu. **Installed Apps** and **Sniff Log** are
    /// developer tools (Tizen app-ID harvesting + raw WebSocket traffic), so they're only
    /// surfaced in DEBUG builds; release builds get just Hidden + Shortcuts.
    static var selectableCases: [SidePanelMode] {
        #if DEBUG
        allCases
        #else
        []
        #endif
    }

    var label: LocalizedStringKey {
        switch self {
        case .none:           "Hidden"
        case .shortcuts:      "Shortcuts"
        case .installedApps:  "Installed Apps"
        case .sniffLog:       "Sniff Log"
        }
    }

    var systemImage: String {
        switch self {
        case .none:           "rectangle"
        case .shortcuts:      "star.fill"
        case .installedApps:  "square.grid.2x2"
        case .sniffLog:       "doc.text.magnifyingglass"
        }
    }
}
