import Foundation
import Testing
@testable import RemoteTV

@MainActor
private final class FakeTVService: TVService {
    var state: TVConnectionState = .disconnected
    var tvPowerState: TVPowerState = .unknown
    var sniffLog: [SniffLogEntry] = []
    var sentCommands: [TVCommand] = []
    var sentTexts: [String] = []
    var launchedAppIDs: [String] = []
    var forgottenDeviceIDs: [String] = []
    var connectError: (any Error)?
    var sendError: (any Error)?
    var launchError: (any Error)?
    var installedAppsResult: Result<[InstalledApp], any Error> = .success([])
    var reconnectCallCount: Int = 0

    func connect(to device: TVDevice) async throws {
        if let error = connectError { throw error }
        state = .connected
    }

    func send(_ command: TVCommand) async throws {
        if let error = sendError { throw error }
        sentCommands.append(command)
    }

    func sendText(_ text: String) async throws {
        if let error = sendError { throw error }
        sentTexts.append(text)
    }

    var sentRawKeys: [(code: String, hold: Bool)] = []
    func sendRawKey(_ keyCode: String, hold: Bool) async throws {
        if let error = sendError { throw error }
        sentRawKeys.append((keyCode, hold))
    }

    var voiceSessionsBegun = 0
    var voiceChunks: [Data] = []
    var voiceSessionsEnded = 0
    func beginVoiceSession() async throws {
        if let error = sendError { throw error }
        voiceSessionsBegun += 1
    }
    func sendVoiceChunk(_ pcm: Data) async throws {
        voiceChunks.append(pcm)
    }
    func endVoiceSession() async {
        voiceSessionsEnded += 1
    }

    func launch(appID: String) async throws {
        if let error = launchError { throw error }
        launchedAppIDs.append(appID)
    }

    var castedYouTubeVideos: [(videoId: String, listId: String?, startSeconds: Int)] = []
    func castYouTubeVideo(videoId: String, listId: String?, startSeconds: Int) async throws {
        if let error = launchError { throw error }
        castedYouTubeVideos.append((videoId, listId, startSeconds))
    }

    func requestInstalledApps() async throws -> [InstalledApp] {
        try installedAppsResult.get()
    }

    func clearSniffLog() {
        sniffLog.removeAll()
    }

    func disconnect() async {
        state = .disconnected
    }

    func forget(_ device: TVDevice) async {
        forgottenDeviceIDs.append(device.id)
    }

    func reconnectIfNeeded() async {
        reconnectCallCount += 1
    }
}

@MainActor
struct RemoteViewModelTests {
    private func makeDevice() -> TVDevice {
        TVDevice(ip: "192.168.1.42", name: "Living Room", mode: .plain)
    }

    @Test func sendForwardsCommandToService() async {
        let service = FakeTVService()
        service.state = .connected
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.send(.volumeUp)

        #expect(service.sentCommands == [.volumeUp])
        #expect(vm.lastError == nil)
    }

    @Test func sendSurfacesErrorMessageWhenServiceThrows() async {
        let service = FakeTVService()
        service.sendError = TVServiceError.notConnected
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.send(.volumeUp)

        #expect(vm.lastError != nil)
    }

    @Test func sendClearsPreviousErrorOnSuccess() async {
        let service = FakeTVService()
        service.sendError = TVServiceError.notConnected
        let vm = RemoteViewModel(device: makeDevice(), service: service)
        await vm.send(.volumeUp)
        #expect(vm.lastError != nil)

        service.sendError = nil
        service.state = .connected
        await vm.send(.volumeUp)

        #expect(vm.lastError == nil)
    }

    @Test func forgetTVDelegatesToService() async {
        let service = FakeTVService()
        let device = makeDevice()
        let vm = RemoteViewModel(device: device, service: service)

        await vm.forgetTV()

        #expect(service.forgottenDeviceIDs == [device.id])
    }

    @Test func disconnectDelegatesToService() async {
        let service = FakeTVService()
        service.state = .connected
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.disconnect()

        #expect(service.state == .disconnected)
    }

    @Test func stateReflectsService() async {
        let service = FakeTVService()
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        #expect(vm.state == .disconnected)
        service.state = .awaitingPairing
        #expect(vm.state == .awaitingPairing)
    }

    @Test func refreshInstalledAppsPopulatesList() async {
        let service = FakeTVService()
        let apps = [
            InstalledApp(appID: "111299001912", name: "YouTube"),
            InstalledApp(appID: "3201907018807", name: "Netflix"),
        ]
        service.installedAppsResult = .success(apps)
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.refreshInstalledApps()

        #expect(vm.installedApps == apps)
        #expect(vm.isLoadingInstalledApps == false)
        #expect(vm.lastError == nil)
    }

    @Test func refreshInstalledAppsSurfacesError() async {
        let service = FakeTVService()
        service.installedAppsResult = .failure(TVServiceError.notConnected)
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.refreshInstalledApps()

        #expect(vm.installedApps == nil)
        #expect(vm.lastError != nil)
    }

    @Test func launchAppForwardsAppIDToService() async {
        let service = FakeTVService()
        service.state = .connected
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.launchApp(appID: "111299001912")

        #expect(service.launchedAppIDs == ["111299001912"])
    }

    @Test func goLiveSendsExitThenLiveTV() async {
        let service = FakeTVService()
        service.state = .connected
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.goLive()

        #expect(service.sentCommands == [.exit, .liveTV])
    }

    @Test func reconnectIfNeededDelegatesToService() async {
        let service = FakeTVService()
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.reconnectIfNeeded()

        #expect(service.reconnectCallCount == 1)
    }

    @Test func parseYouTubeExtractsVideoListAndTime() {
        let parsed = RemoteViewModel.parseYouTube(
            from: "https://www.youtube.com/watch?v=qUundAa9j4M&list=RDqUundAa9j4M&start_radio=1&t=2649s"
        )
        #expect(parsed?.videoId == "qUundAa9j4M")
        #expect(parsed?.listId == "RDqUundAa9j4M")
        #expect(parsed?.startSeconds == 2649)
    }

    @Test func parseYouTubeOmitsMissingKeys() {
        let parsed = RemoteViewModel.parseYouTube(from: "https://www.youtube.com/watch?v=abc123")
        #expect(parsed?.videoId == "abc123")
        #expect(parsed?.listId == nil)
        #expect(parsed?.startSeconds == 0)
    }

    @Test func parseYouTubeNilWithoutVideoId() {
        #expect(RemoteViewModel.parseYouTube(from: "https://www.youtube.com/feed/trending") == nil)
    }

    @Test func castYouTubeForwardsParsedVideoToService() async {
        let service = FakeTVService()
        service.state = .connected
        let vm = RemoteViewModel(device: makeDevice(), service: service)

        await vm.castYouTube()

        // Assert against whatever the demo URL constant parses to, so editing the
        // constant (it's swapped around while experimenting) doesn't break the test.
        let expected = RemoteViewModel.parseYouTube(from: RemoteViewModel.youtubeCastURL)
        #expect(service.castedYouTubeVideos.count == 1)
        #expect(service.castedYouTubeVideos.first?.videoId == expected?.videoId)
        #expect(service.castedYouTubeVideos.first?.listId == expected?.listId)
        #expect(service.castedYouTubeVideos.first?.startSeconds == expected?.startSeconds)
        #expect(vm.lastError == nil)
    }

    @Test func reconnectIfNeededClearsLastErrorOnRecovery() async {
        let service = FakeTVService()
        service.sendError = TVServiceError.notConnected
        let vm = RemoteViewModel(device: makeDevice(), service: service)
        await vm.send(.up)
        #expect(vm.lastError != nil)

        // Simulate the service successfully reconnecting via the scene-phase hook —
        // the banner should clear so the UI doesn't show a stale "not connected".
        service.sendError = nil
        service.state = .connected
        await vm.reconnectIfNeeded()

        #expect(vm.lastError == nil)
    }
}
