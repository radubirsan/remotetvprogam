import Foundation
import Testing
@testable import RemoteTV

@MainActor
private final class FakeTVService: TVService {
    var state: TVConnectionState = .disconnected
    var sniffLog: [SniffLogEntry] = []
    var sentCommands: [TVCommand] = []
    var launchedAppIDs: [String] = []
    var forgottenDeviceIDs: [String] = []
    var connectError: (any Error)?
    var sendError: (any Error)?
    var launchError: (any Error)?
    var installedAppsResult: Result<[InstalledApp], any Error> = .success([])

    func connect(to device: TVDevice) async throws {
        if let error = connectError { throw error }
        state = .connected
    }

    func send(_ command: TVCommand) async throws {
        if let error = sendError { throw error }
        sentCommands.append(command)
    }

    func launch(appID: String) async throws {
        if let error = launchError { throw error }
        launchedAppIDs.append(appID)
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
}
