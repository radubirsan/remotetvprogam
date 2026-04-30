import SwiftUI

/// Side-panel rendering of the hardcoded ``TVApp`` shortcuts (Netflix, Disney+,
/// YouTube). Lives on the left of the remote, mutually exclusive with the other
/// side panels. Useful when the dynamic ``InstalledAppsSection`` probe doesn't
/// surface an app the user knows is installed — these are the bare-IDs that
/// Samsung's `applications` REST endpoint accepts directly on every modern Tizen
/// build we've tested.
@MainActor
struct RemoteSidePanelShortcuts: View {
    let onLaunch: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcuts")
                .font(.title3.bold())
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                ForEach(TVApp.allCases) { app in
                    Button {
                        Task { await onLaunch(app.appID) }
                    } label: {
                        Text(app.displayName)
                            .bold()
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint(for: app))
                    .accessibilityLabel(Text("Launch \(app.displayName)"))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RemoteTheme.body.opacity(0.5))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .colorScheme(.dark)
    }

    private func tint(for app: TVApp) -> Color {
        switch app {
        case .netflix:    .red
        case .disneyPlus: .blue
        case .youtube:    .pink
        }
    }
}
