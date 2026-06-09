import Foundation
import Observation

/// Drives the first-run setup wizard: network check → find TV → pair → success →
/// test → optimize. Re-used for the "Setup guide" replay from the gear menu (`isReplay`).
///
/// Reuses the app's real services — discovery, the `TVService` (whose `connect` triggers the
/// TV's Allow popup and persists the pairing token), and the remembered-TVs store (for names
/// and the WoL MAC). The pairing step simply `await`s `service.connect`: while it's in flight
/// the view reflects `connectionState` (`.connecting` → `.awaitingPairing` → `.connected`),
/// and the call returns once paired, so the VM advances to the success animation.
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome, network, findTV, pair, success, test, optimize

        /// Steps that get a progress dot (pair/success are transient, not user-driven).
        static let milestones: [Step] = [.welcome, .network, .findTV, .test, .optimize]
    }

    private(set) var step: Step = .welcome
    /// True when launched from the gear menu with a TV already set up — lets the flow skip
    /// straight past pairing if the user just wants the settings guide.
    let isReplay: Bool

    // MARK: Network
    let networkMonitor = NetworkMonitor()
    var isOnWiFi: Bool { networkMonitor.isOnLocalNetwork }

    // MARK: Discovery
    private(set) var discoveredTVs: [DiscoveredTV] = []
    private(set) var isSearching = false
    private(set) var searchTimedOut = false
    var manualIP: String = ""
    var showManualEntry = false

    // MARK: Pairing
    private(set) var selectedDevice: TVDevice?
    private(set) var pairingFailed = false
    var connectionState: TVConnectionState { service.state }

    // MARK: Test
    private(set) var testResult: Bool?

    private let service: any TVService
    private let discovery: any TVDiscoveryService
    private let rememberedTVsStore: any RememberedTVsStore
    /// 2019+ Samsung models speak `wss://…:8002`; that's the overwhelming majority now, so
    /// onboarding pairs in secure mode. Older `ws://:8001` sets can still be added from the
    /// Discovery screen's mode picker if the guide can't reach them.
    private let mode: TVConnectionMode = .secure

    private var remembered: [RememberedTV] = []
    private var discoveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let searchTimeout: Duration = .seconds(12)

    init(
        service: any TVService,
        discovery: any TVDiscoveryService,
        rememberedTVsStore: any RememberedTVsStore,
        isReplay: Bool
    ) {
        self.service = service
        self.discovery = discovery
        self.rememberedTVsStore = rememberedTVsStore
        self.isReplay = isReplay
    }

    // MARK: - Navigation

    var canAdvanceFromNetwork: Bool { isOnWiFi }

    /// Moves to `step`, running its entry side effects (start/stop discovery, kick off pairing).
    func go(to newStep: Step) async {
        // Leaving findTV always stops the scan.
        if step == .findTV, newStep != .findTV { await stopDiscovery() }
        step = newStep
        switch newStep {
        case .findTV: await startDiscovery()
        case .pair:   await pair()
        default:      break
        }
    }

    func continueFromWelcome() async { await go(to: .network) }
    func continueFromNetwork() async { await go(to: .findTV) }
    func continueFromSuccess() async { await go(to: .test) }
    func continueFromTest() async { await go(to: .optimize) }

    // MARK: - Discovery

    private func startDiscovery() async {
        discoveredTVs = []
        searchTimedOut = false
        isSearching = true
        remembered = await rememberedTVsStore.all()

        let stream = await discovery.discoveries()
        await discovery.start()
        discoveryTask = Task { [weak self] in
            for await tv in stream {
                guard !Task.isCancelled else { return }
                self?.didDiscover(tv)
            }
        }
        let timeout = searchTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.searchTimedOut = true
        }
    }

    private func didDiscover(_ tv: DiscoveredTV) {
        guard !discoveredTVs.contains(where: { $0.ip == tv.ip }) else { return }
        discoveredTVs.append(tv)
    }

    func stopDiscovery() async {
        discoveryTask?.cancel(); discoveryTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        await discovery.stop()
        isSearching = false
    }

    func retrySearch() async { await startDiscovery() }

    // MARK: - Selection / pairing

    func selectTV(_ tv: DiscoveredTV) async {
        let mac = remembered.first { $0.ip == tv.ip || $0.udn == tv.udn }?.mac
        selectedDevice = TVDevice(
            ip: tv.ip,
            name: tv.friendlyName.isEmpty ? "Samsung TV" : tv.friendlyName,
            mode: mode,
            mac: mac
        )
        await go(to: .pair)
    }

    func useManualIP() async {
        let trimmed = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = remembered.first { $0.ip == trimmed }
        selectedDevice = TVDevice(
            ip: trimmed,
            name: record?.friendlyName ?? "Samsung TV",
            mode: mode,
            mac: record?.mac
        )
        await go(to: .pair)
    }

    /// Connects to the selected TV. `connect` opens the handshake (TV shows its Allow popup,
    /// surfaced as `.awaitingPairing`) and returns once paired — so a clean return means we
    /// advance to the success animation; a throw means pairing failed and we offer a retry.
    private func pair() async {
        guard let device = selectedDevice else { return }
        pairingFailed = false
        do {
            try await service.connect(to: device)
            step = .success
        } catch {
            pairingFailed = true
        }
    }

    func retryPairing() async { await pair() }

    /// Bail out of pairing back to the TV list (e.g. user picked the wrong TV).
    func backToFind() async { await go(to: .findTV) }

    // MARK: - Test

    func sendTestKey() async {
        try? await service.send(.volumeUp)
    }

    func recordTestResult(_ success: Bool) {
        testResult = success
    }
}
