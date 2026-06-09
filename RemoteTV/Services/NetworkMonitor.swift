import Foundation
import Network
import Observation

/// Watches the device's network path and tells the UI whether the phone can currently
/// reach a TV on the **local network**.
///
/// A Samsung TV lives on the LAN, so it's only reachable when the phone has a Wi-Fi (or
/// wired) path — **not** over cellular. So `isOnLocalNetwork` is true only when there's a
/// satisfied path that uses Wi-Fi/Ethernet; it goes false when Wi-Fi is switched off (even
/// if cellular is up) or there's no connectivity at all. ``RootView`` overlays a "join the
/// TV's Wi-Fi" prompt while it's false, so a user with Wi-Fi accidentally off isn't left
/// staring at a dead remote wondering what broke.
@MainActor
@Observable
final class NetworkMonitor {
    /// Whether the phone has a usable LAN path right now. Starts `true` so the overlay
    /// doesn't flash on launch before the first path evaluation arrives.
    private(set) var isOnLocalNetwork = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.remotetv.networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // `.satisfied` alone isn't enough — cellular-only is satisfied but can't reach a
            // LAN TV. Require an actual Wi-Fi/wired interface. (No-internet Wi-Fi still counts:
            // the path stays satisfied over Wi-Fi, and a local TV doesn't need the internet.)
            let onLAN = path.status == .satisfied
                && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor [weak self] in
                self?.isOnLocalNetwork = onLAN
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
