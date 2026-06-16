import RemoteTVCore
import SwiftUI

/// On-demand list of apps detected on the TV. The first tap of "Load Installed Apps" fires
/// parallel REST probes against the curated ``KnownTVApps`` catalog; subsequent taps clear
/// the cache and re-probe, so the user can refresh after installing or uninstalling an app.
struct InstalledAppsSection: View {
    let installedApps: [InstalledApp]?
    let isLoading: Bool
    let onRefresh: () async -> Void
    let onLaunch: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                Task { await onRefresh() }
            } label: {
                Label(buttonTitle, systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoading)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let apps = installedApps {
                if apps.isEmpty {
                    Text("No apps reported by the TV.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(apps) { app in
                                Button {
                                    Task { await onLaunch(app.appID) }
                                } label: {
                                    Text(app.name)
                                        .lineLimit(1)
                                        .frame(minWidth: 80, minHeight: 40)
                                        .padding(.horizontal)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(Text("Launch \(app.name)"))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var buttonTitle: LocalizedStringKey {
        if installedApps != nil {
            return "Refresh Installed Apps"
        }
        return "Load Installed Apps"
    }
}
