import SwiftUI

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

    var body: some View {
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
