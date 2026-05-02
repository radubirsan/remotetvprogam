import Foundation
import Observation

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

    init(device: TVDevice, service: any TVService) {
        self.device = device
        self.service = service
    }

    var state: TVConnectionState { service.state }
    var mode: TVConnectionMode { device.mode }
    var sniffLog: [SniffLogEntry] { service.sniffLog }
    var tvPowerState: TVPowerState { service.tvPowerState }

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
