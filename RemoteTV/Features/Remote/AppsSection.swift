import RemoteTVCore
import SwiftUI

/// One-tap shortcuts for the streaming apps we expose (Netflix, Disney+, YouTube). Mirrors
/// the dedicated app buttons on Samsung's physical remote.
struct AppsSection: View {
    let onLaunch: (String) async -> Void

    var body: some View {
        HStack {
            ForEach(TVApp.allCases) { app in
                Button {
                    Task { await onLaunch(app.appID) }
                } label: {
                    Text(app.displayName)
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(tint(for: app))
                .accessibilityLabel(Text("Launch \(app.displayName)"))
            }
        }
    }

    private func tint(for app: TVApp) -> Color {
        switch app {
        case .netflix: .red
        case .disneyPlus: .blue
        case .youtube: .pink
        }
    }
}
