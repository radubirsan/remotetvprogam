import RemoteTVCore
import SwiftUI

/// Side-panel rendering of the installed-apps loader. Used when the user opens the
/// "Installed Apps" panel from the gear menu — sits to the *left* of the remote and
/// fills its column. Vertical button stack (vs the embedded
/// ``InstalledAppsSection``'s horizontal scroll) so the column can usefully display
/// the full list without secondary scrolling.
@MainActor
struct RemoteSidePanelInstalledApps: View {
    let installedApps: [InstalledApp]?
    let isLoading: Bool
    let onRefresh: () async -> Void
    let onLaunch: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed Apps")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Button {
                Task { await onRefresh() }
            } label: {
                Label(loadButtonTitle, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if let apps = installedApps {
                if apps.isEmpty {
                    Text("No apps reported by the TV.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(apps) { app in
                                Button {
                                    Task { await onLaunch(app.appID) }
                                } label: {
                                    Text(app.name)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(Text("Launch \(app.name)"))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                Text("Tap Load to fetch the apps installed on the TV.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

    private var loadButtonTitle: LocalizedStringKey {
        installedApps == nil ? "Load Apps" : "Refresh"
    }
}
