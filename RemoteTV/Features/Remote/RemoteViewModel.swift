import Foundation
import Observation

/// What happened the last time the user pressed the power button while the
/// view model was in "wake" mode. Surfaced on `RemoteViewModel.lastError` for the
/// non-`.sent` cases so the UI's existing error path can render the message.
enum RemoteWakeOutcome: Equatable, Sendable {
    /// Magic packet was dispatched (delivery is best-effort — UDP, no ack).
    case sent
    /// We don't have the TV's MAC on file yet; user must connect once with the TV
    /// awake so the app can capture it via the REST info endpoint.
    case macUnknown
    /// No wake service was injected — composition error in the host app.
    case wakeServiceMissing
    /// The wake service threw — usually a network failure (Wi-Fi dropped, etc.).
    case failed(String)
}

@MainActor
@Observable
final class RemoteViewModel {
    let device: TVDevice
    let service: any TVService
    private(set) var lastError: String?
    /// Non-nil while a "Mute 2 Min" timer is running. Drives the big-button UI.
    private(set) var commercialMuteRemaining: Duration?
    /// Nil until the user has asked the TV for its app list at least once.
    private(set) var installedApps: [InstalledApp]?
    private(set) var isLoadingInstalledApps: Bool = false

    private var commercialMuteTask: Task<Void, Never>?
    private let commercialMuteDurationSeconds: Int = 120
    /// Optional — when injected, the power button switches to "wake mode" while the
    /// WebSocket isn't reachable, and a tap fires a Wake-on-LAN magic packet instead
    /// of `KEY_POWER`. Nil in tests or in any host that doesn't ship a wake service.
    private let wakeService: (any WakeOnLANService)?
    /// Optional — used by ``wakeAndReconnect()`` to look up the TV's MAC by IP.
    /// The MAC is captured into the remembered-TVs store on the first successful
    /// connect, so a freshly-paired TV becomes wakeable from then on.
    private let rememberedTVsStore: (any RememberedTVsStore)?
    /// How long to wait after sending a magic packet before retrying `connect()` —
    /// gives the TV time to bring its NIC up and accept the WebSocket.
    private let postWakeReconnectDelay: Duration = .seconds(5)

    init(
        device: TVDevice,
        service: any TVService,
        wakeService: (any WakeOnLANService)? = nil,
        rememberedTVsStore: (any RememberedTVsStore)? = nil
    ) {
        self.device = device
        self.service = service
        self.wakeService = wakeService
        self.rememberedTVsStore = rememberedTVsStore
    }

    var state: TVConnectionState { service.state }
    var mode: TVConnectionMode { device.mode }
    var sniffLog: [SniffLogEntry] { service.sniffLog }
    var tvPowerState: TVPowerState { service.tvPowerState }

    /// True when the WebSocket is unreachable — the TV is presumed off (or the
    /// network blipped) and `KEY_POWER` over the WS would be a no-op. The view
    /// uses this to swap the power button into wake mode (amber ring, WoL action
    /// on tap, help sheet on long-press).
    var isInWakeMode: Bool {
        switch service.state {
        case .disconnected, .failed: true
        case .connecting, .awaitingPairing, .connected: false
        }
    }

    func clearSniffLog() {
        service.clearSniffLog()
    }

    /// Kicks off the WebSocket handshake. Called from ``RemoteView``'s `.task` so the connect
    /// attempt starts the moment the user pushes into the remote — the `StatusPill` animates
    /// through `.connecting` → `.awaitingPairing` → `.connected` as the service drives state.
    func connect() async {
        do {
            try await service.connect(to: device)
            lastError = nil
        } catch let error as TVServiceError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func send(_ command: TVCommand) async {
        do {
            try await service.send(command)
            lastError = nil
        } catch let error as TVServiceError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func launchApp(appID: String) async {
        do {
            try await service.launch(appID: appID)
            lastError = nil
        } catch let error as TVServiceError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// "Get me back to live TV" — a compound action that works from inside apps that would
    /// otherwise swallow `KEY_TV`. First sends `KEY_EXIT` (apps generally let this bubble
    /// up to Tizen), waits for the app to tear down, then selects the tuner with `KEY_TV`.
    /// Pressing `KEY_TV` alone from inside Netflix/HBO does nothing because the app has
    /// input focus and doesn't handle that key.
    func goLive() async {
        await send(.exit)
        try? await Task.sleep(for: .milliseconds(500))
        await send(.liveTV)
    }

    func disconnect() async {
        cancelCommercialMute()
        await service.disconnect()
    }

    /// Hook for the view's scene-phase observer. Called every time the app comes back
    /// to `.active` so the service can transparently re-handshake if iOS killed the
    /// WebSocket while the app was suspended (lock screen, app-switcher). Resolves the
    /// outer error banner on a successful reconnect so the UI doesn't show a stale
    /// failure.
    func reconnectIfNeeded() async {
        await service.reconnectIfNeeded()
        if service.state == .connected {
            lastError = nil
        }
    }

    func forgetTV() async {
        await service.forget(device)
    }

    /// Routed by `PowerButton`'s tap. In normal (connected) operation this fires
    /// `KEY_POWER` over the WebSocket; when ``isInWakeMode`` is true the WebSocket
    /// is presumed dead so we send a Wake-on-LAN magic packet instead and try to
    /// reconnect after a short delay.
    func handlePowerTap() async {
        if isInWakeMode {
            await wakeAndReconnect()
        } else {
            await send(.power)
        }
    }

    /// Sends a Wake-on-LAN magic packet to the TV's stored MAC and, on success,
    /// kicks off a reconnect attempt after ``postWakeReconnectDelay`` so the user
    /// doesn't have to back out and re-enter the remote view to recover the
    /// WebSocket once the TV finishes booting.
    func wakeAndReconnect() async {
        let outcome = await sendWake()
        switch outcome {
        case .sent:
            lastError = nil
            try? await Task.sleep(for: postWakeReconnectDelay)
            await connect()
        case .macUnknown:
            lastError = "Connect once while the TV is on so the app can capture its MAC."
        case .wakeServiceMissing:
            lastError = "Wake-on-LAN isn't available in this build."
        case .failed(let message):
            lastError = "Wake failed: \(message)"
        }
    }

    /// Pure dispatch path — no UI state side effects. Returns the outcome so callers
    /// can present feedback their own way (the view model itself surfaces it via
    /// `lastError`, but a unit test can assert on the outcome directly).
    func sendWake() async -> RemoteWakeOutcome {
        guard let wakeService else { return .wakeServiceMissing }
        let mac: String? = await rememberedTVsStore?.get(ip: device.ip)?.mac
        guard let mac, !mac.isEmpty else { return .macUnknown }
        do {
            try await wakeService.wake(mac: mac, ip: device.ip)
            return .sent
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Toggles a 2-minute "commercial break" mute. Sends `KEY_MUTE` immediately and again
    /// once the timer elapses — Samsung's mute key is a toggle, so the second press restores
    /// audio. Tapping the button while the timer is running cancels early and unmutes now.
    func toggleCommercialMute() async {
        if commercialMuteRemaining != nil {
            cancelCommercialMute()
            await send(.mute)
            return
        }

        await send(.mute)
        let total = commercialMuteDurationSeconds
        commercialMuteRemaining = .seconds(total)

        commercialMuteTask = Task { [weak self] in
            for remaining in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                if remaining > 0 {
                    self.commercialMuteRemaining = .seconds(remaining)
                }
            }
            guard let self else { return }
            self.commercialMuteRemaining = nil
            self.commercialMuteTask = nil
            await self.send(.mute)
        }
    }

    /// Clears any cached app list and asks the TV for a fresh one. Per the UI spec: one tap
    /// loads, subsequent taps clear-and-reload — so the user can refresh after installing or
    /// uninstalling an app on the TV without tearing down the connection.
    func refreshInstalledApps() async {
        installedApps = nil
        isLoadingInstalledApps = true
        defer { isLoadingInstalledApps = false }

        do {
            let apps = try await service.requestInstalledApps()
            installedApps = apps
            lastError = nil
        } catch let error as TVServiceError {
            lastError = error.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func cancelCommercialMute() {
        commercialMuteTask?.cancel()
        commercialMuteTask = nil
        commercialMuteRemaining = nil
    }
}
