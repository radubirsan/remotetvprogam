import SwiftUI
import UIKit

/// Top-level view that flips between the two app modes based on whether the user has
/// a TV "set up" — the Discovery flow is for finding a TV, the Remote flow is for
/// using one. Once a TV is chosen, the app stays in the Remote flow across cold
/// launches; the only way back to Discovery is the gear menu's *Disconnect & switch
/// mode* (or *Forget this TV*) action.
///
/// The active TV is persisted as JSON in `@AppStorage("lastRemoteDeviceJSON")` —
/// non-empty means "render `RemoteView`," empty means "render `DiscoveryView`." The
/// switch happens in-place: `DiscoveryView` writes the value when the user picks a
/// TV; `RemoteView` clears it when the user disconnects or forgets. No
/// `NavigationStack` between the two — neither is a child of the other, so there's
/// no back chevron to confuse the user.
@MainActor
struct RootView: View {
    let service: any TVService
    let discovery: any TVDiscoveryService
    let rememberedTVsStore: any RememberedTVsStore
    let wakeService: any WakeOnLANService

    /// JSON-encoded ``TVDevice`` of the active TV. Empty string ⇒ no active TV ⇒
    /// show Discovery. Stored as `String` (not `Data?`) so the value stays trivially
    /// human-readable in `defaults read` while still round-tripping through `Codable`.
    @AppStorage("lastRemoteDeviceJSON") private var lastRemoteDeviceJSON: String = ""

    /// Watches the phone's network path. When Wi-Fi is off (so the LAN TV is unreachable),
    /// we cover the whole app with ``WiFiRequiredView`` rather than letting the remote look
    /// silently broken — the exact confusion that prompted this.
    @State private var networkMonitor = NetworkMonitor()

    var body: some View {
        content
            .overlay {
                if !networkMonitor.isOnLocalNetwork {
                    WiFiRequiredView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: networkMonitor.isOnLocalNetwork)
    }

    @ViewBuilder
    private var content: some View {
        if let device = decodedDevice {
            RemoteView(
                device: device,
                service: service,
                wakeService: wakeService,
                rememberedTVsStore: rememberedTVsStore,
                onDisconnect: clearActiveDevice
            )
            // Force a fresh `RemoteView` instance if the user disconnects and
            // immediately picks a different TV — without `.id`, SwiftUI would reuse
            // the existing view and skip the `.task` that drives `connect()`.
            .id(device.id)
        } else {
            DiscoveryView(
                service: service,
                discovery: discovery,
                rememberedTVsStore: rememberedTVsStore,
                wakeService: wakeService,
                onConnect: persistActiveDevice
            )
        }
    }

    private var decodedDevice: TVDevice? {
        guard !lastRemoteDeviceJSON.isEmpty else { return nil }
        let data = Data(lastRemoteDeviceJSON.utf8)
        return try? JSONDecoder().decode(TVDevice.self, from: data)
    }

    private func persistActiveDevice(_ device: TVDevice) {
        guard
            let data = try? JSONEncoder().encode(device),
            let json = String(data: data, encoding: .utf8)
        else { return }
        lastRemoteDeviceJSON = json
    }

    private func clearActiveDevice() {
        lastRemoteDeviceJSON = ""
    }
}

/// Full-screen takeover shown whenever the phone has no Wi-Fi/LAN path. It auto-dismisses
/// (via ``RootView``'s reactive overlay) the moment Wi-Fi comes back, so there's nothing to
/// tap to clear it — fixing the "remote looks dead but it's just Wi-Fi off" trap.
private struct WiFiRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            RemoteTheme.bg.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .symbolRenderingMode(.hierarchical)

                Text("No Wi-Fi Connection")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Your iPhone isn’t on Wi-Fi. Connect it to the **same Wi-Fi network as your TV** — the remote can’t reach the TV over cellular.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open Settings")
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
        .preferredColorScheme(.dark)
        // Sit above everything (incl. the Remote's nav bar) and swallow taps so stray
        // presses don't leak through to the disabled remote behind it.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("No Wi-Fi connection. Connect your iPhone to the same Wi-Fi network as your TV."))
    }
}
