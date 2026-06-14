import Foundation

/// Failures surfaced to Siri / Shortcuts as a spoken + displayed message. Service-layer
/// errors (``TVServiceError``) already speak `LocalizedError` and pass through as-is;
/// these cover the intent-specific cases that happen before the service is reached.
enum TVIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// No `lastRemoteDeviceJSON` on file — the user has never connected to a TV.
    case noTVConfigured
    /// TV unreachable and no MAC on file, so Wake-on-LAN can't be attempted.
    case macUnknown
    /// TV unreachable and no wake service was injected.
    case wakeUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTVConfigured:
            "No TV is set up yet. Open RemoteTV and connect to your TV once first."
        case .macUnknown:
            "The TV is unreachable and its network address isn't on file yet. Connect once while the TV is on, then waking will work."
        case .wakeUnavailable:
            "The TV is unreachable and Wake-on-LAN isn't available."
        }
    }
}

/// Shared backend for every App Intent: resolves the last-used TV, brings the WebSocket
/// up on demand, and routes commands. Registered with `AppDependencyManager` in
/// ``RemoteTVApp/init()`` wrapping the *same* `SamsungTVService` instance the UI uses —
/// so an intent fired while the app is foregrounded reuses the live connection instead
/// of opening a second socket, and a background launch connects fresh.
@MainActor
final class TVIntentsController {
    /// What ``togglePower()`` actually did, so the intent can word its dialog honestly.
    enum PowerOutcome: Equatable {
        /// `KEY_POWER` went over a live socket (TV toggles standby).
        case sentPowerKey
        /// The TV was unreachable/off — a Wake-on-LAN magic packet was sent instead.
        case sentWakePacket
    }

    /// Matches `RemoteView.tuneInterKeyDelay` — the TV drops digits that arrive as a
    /// racing batch, so macros pace their keys.
    static let interKeyDelay: Duration = .milliseconds(120)

    private let service: any TVService
    private let wakeService: (any WakeOnLANService)?
    private let rememberedTVsStore: (any RememberedTVsStore)?
    /// Injected so tests can supply a fixture; reads from ``SharedStorage`` so the App
    /// Group suite (Control Center extension) and the app's defaults are both covered.
    private let loadDeviceJSON: () -> String?

    init(
        service: any TVService,
        wakeService: (any WakeOnLANService)? = nil,
        rememberedTVsStore: (any RememberedTVsStore)? = nil,
        loadDeviceJSON: @escaping () -> String? = { SharedStorage.lastRemoteDeviceJSON }
    ) {
        self.service = service
        self.wakeService = wakeService
        self.rememberedTVsStore = rememberedTVsStore
        self.loadDeviceJSON = loadDeviceJSON
    }

    // MARK: - Cross-process resolution

    /// The app sets this in `RemoteTVApp.init` so in-app and Siri intents reuse the SAME
    /// live `SamsungTVService` the UI drives (a foregrounded mute reuses the open socket
    /// instead of opening a second one). Stays `nil` in the widget-extension process.
    @MainActor static var shared: TVIntentsController?

    /// The controller an intent should use, regardless of which process it runs in:
    /// the app's live controller when available, otherwise a fresh stack built from
    /// shared storage. Replaces `@Dependency`, which traps in the extension because
    /// `AppDependencyManager` is only populated in the app process.
    @MainActor static func resolve() -> TVIntentsController {
        shared ?? makeStandalone()
    }

    /// Builds a self-contained controller from persistent state — a safety net for any
    /// intent that runs without `shared` set (no running app to borrow a live service
    /// from). Reads the pairing token via the shared Keychain access group and the last
    /// device from the App Group suite. (The Control Center extension is currently
    /// self-contained and doesn't use this; it stays for Siri/Shortcuts robustness and as
    /// the seam for a future shared-package extension.)
    @MainActor static func makeStandalone() -> TVIntentsController {
        let tokenStore = KeychainTVTokenStore(accessGroup: SharedStorage.keychainAccessGroup)
        let remembered = FileRememberedTVsStore()
        let service = SamsungTVService(
            tokenStore: tokenStore,
            rememberedTVsStore: remembered,
            deviceInfoService: SamsungDeviceInfoService()
        )
        return TVIntentsController(
            service: service,
            wakeService: UDPBroadcastWakeService(),
            rememberedTVsStore: remembered
        )
    }

    /// The TV the app last controlled — the only sensible target for a voice command.
    func lastDevice() throws -> TVDevice {
        guard
            let json = loadDeviceJSON(), !json.isEmpty,
            let device = try? JSONDecoder().decode(TVDevice.self, from: Data(json.utf8))
        else { throw TVIntentError.noTVConfigured }
        return device
    }

    /// Reuses the live socket when there is one, otherwise connects to the last device.
    @discardableResult
    func ensureConnected() async throws -> TVDevice {
        let device = try lastDevice()
        if service.state != .connected {
            try await service.connect(to: device)
        }
        return device
    }

    func send(_ command: TVCommand) async throws {
        try await ensureConnected()
        try await service.send(command)
    }

    /// Sends a multi-key macro (e.g. tune digits + Enter), pacing keys like the UI does.
    func send(macro commands: [TVCommand]) async throws {
        try await ensureConnected()
        for (index, command) in commands.enumerated() {
            try await service.send(command)
            if index < commands.count - 1 {
                try? await Task.sleep(for: Self.interKeyDelay)
            }
        }
    }

    func launchApp(appID: String) async throws {
        try await ensureConnected()
        try await service.launch(appID: appID)
    }

    /// Mirrors the power button's wake-mode logic: `KEY_POWER` over a live socket when
    /// the TV is reachable, a Wake-on-LAN magic packet when it isn't. (`.unknown` power
    /// state right after connect is treated as "on", same as ``RemoteViewModel/isInWakeMode``.)
    func togglePower() async throws -> PowerOutcome {
        let device = try lastDevice()
        do {
            try await ensureConnected()
            if service.tvPowerState != .off {
                try await service.send(.power)
                return .sentPowerKey
            }
        } catch let error as TVIntentError {
            throw error
        } catch {
            // Connect failed — fall through to the wake path below.
        }
        guard let wakeService else { throw TVIntentError.wakeUnavailable }
        var mac = device.mac
        if mac == nil || mac?.isEmpty == true {
            mac = await rememberedTVsStore?.get(ip: device.ip)?.mac
        }
        guard let mac, !mac.isEmpty else { throw TVIntentError.macUnknown }
        try await wakeService.wake(mac: mac, ip: device.ip)
        return .sentWakePacket
    }
}
