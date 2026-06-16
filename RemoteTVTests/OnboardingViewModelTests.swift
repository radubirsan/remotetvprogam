import Foundation
import Testing
import RemoteTVCore
@testable import RemoteTV

// MARK: - Fakes

@MainActor
private final class FakeTVService: TVService {
    var state: TVConnectionState = .disconnected
    var tvPowerState: TVPowerState = .unknown
    var sniffLog: [SniffLogEntry] = []
    var connectError: (any Error)?
    var connectedDevices: [TVDevice] = []
    var sentCommands: [TVCommand] = []

    func connect(to device: TVDevice) async throws {
        connectedDevices.append(device)
        if let error = connectError { throw error }
        state = .connected
    }

    func send(_ command: TVCommand) async throws { sentCommands.append(command) }
    func sendText(_ text: String) async throws {}
    func sendRawKey(_ keyCode: String, hold: Bool) async throws {}
    func beginVoiceSession() async throws {}
    func sendVoiceChunk(_ pcm: Data) async throws {}
    func endVoiceSession() async {}
    func launch(appID: String) async throws {}
    func castYouTubeVideo(videoId: String, listId: String?, startSeconds: Int) async throws {}
    func requestInstalledApps() async throws -> [InstalledApp] { [] }
    func clearSniffLog() {}
    func disconnect() async { state = .disconnected }
    func forget(_ device: TVDevice) async {}
    func reconnectIfNeeded() async {}
}

private final class FakeDiscoveryService: TVDiscoveryService, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<DiscoveredTV>.Continuation?
    private var _startCount = 0

    var startCount: Int { lock.withLock { _startCount } }

    func discoveries() -> AsyncStream<DiscoveredTV> {
        AsyncStream { continuation in
            lock.withLock {
                self.continuation?.finish()
                self.continuation = continuation
            }
        }
    }

    func start() async { lock.withLock { _startCount += 1 } }
    func stop() async {}
}

private actor InMemoryRememberedStore: RememberedTVsStore {
    private var records: [RememberedTV]

    init(_ records: [RememberedTV] = []) { self.records = records }

    func all() async -> [RememberedTV] { records }
    func get(ip: String) async -> RememberedTV? { records.first { $0.ip == ip } }
    func upsert(_ tv: RememberedTV) async throws {
        if let index = records.firstIndex(where: { $0.ip == tv.ip }) {
            records[index] = tv
        } else {
            records.append(tv)
        }
    }
    func delete(ip: String) async throws { records.removeAll { $0.ip == ip } }
}

// MARK: - Tests

@MainActor
struct OnboardingViewModelTests {
    private func makeVM(
        service: FakeTVService = FakeTVService(),
        remembered: [RememberedTV] = []
    ) -> (OnboardingViewModel, FakeTVService, FakeDiscoveryService) {
        let discovery = FakeDiscoveryService()
        let vm = OnboardingViewModel(
            service: service,
            discovery: discovery,
            rememberedTVsStore: InMemoryRememberedStore(remembered),
            isReplay: false
        )
        return (vm, service, discovery)
    }

    @Test func selectTVPairsAndAdvancesToSuccess() async {
        let remembered = RememberedTV(
            ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55",
            mac: "aa:bb:cc:dd:ee:ff", udn: "uuid:abc"
        )
        let (vm, service, _) = makeVM(remembered: [remembered])
        await vm.go(to: .findTV)   // loads remembered records, starts the (fake) scan

        let tv = DiscoveredTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", udn: "uuid:abc")
        await vm.selectTV(tv)

        #expect(vm.step == .success)
        #expect(vm.pairingFailed == false)
        #expect(service.connectedDevices.count == 1)
        let device = service.connectedDevices.first
        #expect(device?.mode == .secure)
        #expect(device?.mac == "aa:bb:cc:dd:ee:ff", "MAC from the remembered record should carry over")
    }

    @Test func selectTVFallsBackToGenericNameWhenTXTOmitsIt() async {
        let (vm, service, _) = makeVM()
        await vm.go(to: .findTV)

        await vm.selectTV(DiscoveredTV(ip: "192.168.1.10", friendlyName: "", modelName: "", udn: "uuid:x"))

        #expect(service.connectedDevices.first?.name == "Samsung TV")
    }

    @Test func pairingFailureSetsFlagAndStaysOnPairStep() async {
        let service = FakeTVService()
        service.connectError = TVServiceError.pairingRejected
        let (vm, _, _) = makeVM(service: service)
        await vm.go(to: .findTV)

        await vm.selectTV(DiscoveredTV(ip: "192.168.1.10", friendlyName: "TV", modelName: "", udn: "uuid:x"))

        #expect(vm.step == .pair)
        #expect(vm.pairingFailed == true)
    }

    @Test func retryPairingRecoversAfterFailure() async {
        let service = FakeTVService()
        service.connectError = TVServiceError.pairingTimeout
        let (vm, _, _) = makeVM(service: service)
        await vm.go(to: .findTV)
        await vm.selectTV(DiscoveredTV(ip: "192.168.1.10", friendlyName: "TV", modelName: "", udn: "uuid:x"))
        #expect(vm.pairingFailed == true)

        service.connectError = nil
        await vm.retryPairing()

        #expect(vm.step == .success)
        #expect(vm.pairingFailed == false)
    }

    @Test func backToFindRestartsDiscovery() async {
        let service = FakeTVService()
        service.connectError = TVServiceError.pairingRejected
        let (vm, _, discovery) = makeVM(service: service)
        await vm.go(to: .findTV)
        await vm.selectTV(DiscoveredTV(ip: "192.168.1.10", friendlyName: "TV", modelName: "", udn: "uuid:x"))

        await vm.backToFind()

        #expect(vm.step == .findTV)
        #expect(discovery.startCount == 2)
    }

    @Test func useManualIPTrimsAndReusesRememberedName() async {
        let remembered = RememberedTV(
            ip: "192.168.1.50", friendlyName: "Bedroom", modelName: "QN90",
            mac: "11:22:33:44:55:66", udn: nil
        )
        let (vm, service, _) = makeVM(remembered: [remembered])
        await vm.go(to: .findTV)

        vm.manualIP = "  192.168.1.50  "
        await vm.useManualIP()

        #expect(vm.step == .success)
        let device = service.connectedDevices.first
        #expect(device?.ip == "192.168.1.50")
        #expect(device?.name == "Bedroom")
        #expect(device?.mac == "11:22:33:44:55:66")
    }

    @Test func useManualIPIgnoresEmptyField() async {
        let (vm, service, _) = makeVM()
        await vm.go(to: .findTV)

        vm.manualIP = "   "
        await vm.useManualIP()

        #expect(vm.step == .findTV)
        #expect(service.connectedDevices.isEmpty)
    }

    @Test func sendTestKeySendsVolumeUp() async {
        let (vm, service, _) = makeVM()

        await vm.sendTestKey()

        #expect(service.sentCommands == [.volumeUp])
    }

    @Test func recordTestResultStoresAnswer() {
        let (vm, _, _) = makeVM()
        #expect(vm.testResult == nil)

        vm.recordTestResult(false)
        #expect(vm.testResult == false)

        vm.recordTestResult(true)
        #expect(vm.testResult == true)
    }
}
