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
    var connectCount = 0
    var sentCommands: [TVCommand] = []
    var launchedAppIDs: [String] = []

    func connect(to device: TVDevice) async throws {
        connectCount += 1
        if let error = connectError { throw error }
        state = .connected
    }

    func send(_ command: TVCommand) async throws { sentCommands.append(command) }
    func sendText(_ text: String) async throws {}
    func sendRawKey(_ keyCode: String, hold: Bool) async throws {}
    func beginVoiceSession() async throws {}
    func sendVoiceChunk(_ pcm: Data) async throws {}
    func endVoiceSession() async {}
    func launch(appID: String) async throws { launchedAppIDs.append(appID) }
    func castYouTubeVideo(videoId: String, listId: String?, startSeconds: Int) async throws {}
    func requestInstalledApps() async throws -> [InstalledApp] { [] }
    func clearSniffLog() {}
    func disconnect() async { state = .disconnected }
    func forget(_ device: TVDevice) async {}
    func reconnectIfNeeded() async {}
}

private final class FakeWakeService: WakeOnLANService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(mac: String, ip: String?)] = []
    var calls: [(mac: String, ip: String?)] { lock.withLock { _calls } }

    func wake(mac: String, ip: String?) async throws {
        lock.withLock { _calls.append((mac, ip)) }
    }
}

private actor InMemoryRememberedStore: RememberedTVsStore {
    private var records: [RememberedTV]
    init(_ records: [RememberedTV] = []) { self.records = records }
    func all() async -> [RememberedTV] { records }
    func get(ip: String) async -> RememberedTV? { records.first { $0.ip == ip } }
    func upsert(_ tv: RememberedTV) async throws {}
    func delete(ip: String) async throws {}
}

// MARK: - Tests

@MainActor
struct TVIntentsControllerTests {
    private func deviceJSON(mac: String? = nil) -> String {
        let device = TVDevice(ip: "192.168.1.42", name: "Living Room", mode: .secure, mac: mac)
        let data = try! JSONEncoder().encode(device)
        return String(decoding: data, as: UTF8.self)
    }

    private func makeController(
        service: FakeTVService,
        wake: FakeWakeService? = nil,
        remembered: [RememberedTV] = [],
        json: String?
    ) -> TVIntentsController {
        TVIntentsController(
            service: service,
            wakeService: wake,
            rememberedTVsStore: InMemoryRememberedStore(remembered),
            loadDeviceJSON: { json }
        )
    }

    @Test func throwsWithoutAStoredDevice() async {
        let controller = makeController(service: FakeTVService(), json: nil)
        await #expect(throws: TVIntentError.self) {
            try await controller.ensureConnected()
        }
    }

    @Test func sendConnectsFirstWhenDisconnected() async throws {
        let service = FakeTVService()
        let controller = makeController(service: service, json: deviceJSON())

        try await controller.send(.mute)

        #expect(service.connectCount == 1)
        #expect(service.sentCommands == [.mute])
    }

    @Test func sendReusesLiveConnection() async throws {
        let service = FakeTVService()
        service.state = .connected
        let controller = makeController(service: service, json: deviceJSON())

        try await controller.send(.mute)

        #expect(service.connectCount == 0, "a live socket must be reused, not reopened")
    }

    @Test func macroSendsCommandsInOrder() async throws {
        let service = FakeTVService()
        service.state = .connected
        let controller = makeController(service: service, json: deviceJSON())

        try await controller.send(macro: [.digit1, .digit0, .digit5, .enter])

        #expect(service.sentCommands == [.digit1, .digit0, .digit5, .enter])
    }

    @Test func launchForwardsAppID() async throws {
        let service = FakeTVService()
        service.state = .connected
        let controller = makeController(service: service, json: deviceJSON())

        try await controller.launchApp(appID: "111299001912")

        #expect(service.launchedAppIDs == ["111299001912"])
    }

    @Test func togglePowerSendsKeyWhenReachable() async throws {
        let service = FakeTVService()
        let controller = makeController(service: service, json: deviceJSON())

        let outcome = try await controller.togglePower()

        #expect(outcome == .sentPowerKey)
        #expect(service.sentCommands == [.power])
    }

    @Test func togglePowerWakesWhenConnectFails() async throws {
        let service = FakeTVService()
        service.connectError = TVServiceError.pairingTimeout
        let wake = FakeWakeService()
        let controller = makeController(
            service: service, wake: wake, json: deviceJSON(mac: "aa:bb:cc:dd:ee:ff")
        )

        let outcome = try await controller.togglePower()

        #expect(outcome == .sentWakePacket)
        #expect(wake.calls.first?.mac == "aa:bb:cc:dd:ee:ff")
        #expect(service.sentCommands.isEmpty)
    }

    @Test func togglePowerWakesWhenTVIsInStandby() async throws {
        // Socket alive but the TV reports standby — KEY_POWER over a stale-standby
        // socket is unreliable, so the wake packet path is taken (same as the UI).
        let service = FakeTVService()
        service.state = .connected
        service.tvPowerState = .off
        let wake = FakeWakeService()
        let controller = makeController(
            service: service, wake: wake, json: deviceJSON(mac: "aa:bb:cc:dd:ee:ff")
        )

        let outcome = try await controller.togglePower()

        #expect(outcome == .sentWakePacket)
    }

    @Test func togglePowerResolvesMACFromRememberedStore() async throws {
        let service = FakeTVService()
        service.connectError = TVServiceError.pairingTimeout
        let wake = FakeWakeService()
        let remembered = RememberedTV(
            ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55",
            mac: "11:22:33:44:55:66", udn: nil
        )
        let controller = makeController(
            service: service, wake: wake, remembered: [remembered], json: deviceJSON()
        )

        let outcome = try await controller.togglePower()

        #expect(outcome == .sentWakePacket)
        #expect(wake.calls.first?.mac == "11:22:33:44:55:66")
    }

    @Test func togglePowerThrowsWhenNoMACAnywhere() async {
        let service = FakeTVService()
        service.connectError = TVServiceError.pairingTimeout
        let controller = makeController(
            service: service, wake: FakeWakeService(), json: deviceJSON()
        )

        await #expect(throws: TVIntentError.self) {
            _ = try await controller.togglePower()
        }
    }
}
