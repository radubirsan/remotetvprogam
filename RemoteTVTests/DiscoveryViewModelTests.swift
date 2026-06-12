import Foundation
import Testing
@testable import RemoteTV

// MARK: - Fakes

private final class FakeDiscoveryService: TVDiscoveryService, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<DiscoveredTV>.Continuation?
    private var _startCount = 0
    private var _stopCount = 0

    var startCount: Int { lock.withLock { _startCount } }
    var stopCount: Int { lock.withLock { _stopCount } }

    func discoveries() -> AsyncStream<DiscoveredTV> {
        AsyncStream { continuation in
            lock.withLock {
                self.continuation?.finish()
                self.continuation = continuation
            }
        }
    }

    func start() async {
        lock.withLock { _startCount += 1 }
    }

    func stop() async {
        lock.withLock { _stopCount += 1 }
    }

    func emit(_ tv: DiscoveredTV) {
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(tv)
    }
}

private actor InMemoryRememberedStore: RememberedTVsStore {
    private var records: [RememberedTV]

    init(_ records: [RememberedTV] = []) {
        self.records = records
    }

    func all() async -> [RememberedTV] { records }

    func get(ip: String) async -> RememberedTV? {
        records.first { $0.ip == ip }
    }

    func upsert(_ tv: RememberedTV) async throws {
        if let index = records.firstIndex(where: { $0.ip == tv.ip }) {
            records[index] = tv
        } else {
            records.append(tv)
        }
    }

    func delete(ip: String) async throws {
        records.removeAll { $0.ip == ip }
    }
}

private final class FakeWakeService: WakeOnLANService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(mac: String, ip: String?)] = []
    private var _error: (any Error)?

    var calls: [(mac: String, ip: String?)] { lock.withLock { _calls } }

    func setError(_ error: (any Error)?) {
        lock.withLock { _error = error }
    }

    func wake(mac: String, ip: String?) async throws {
        let error = lock.withLock {
            _calls.append((mac, ip))
            return _error
        }
        if let error { throw error }
    }
}

// MARK: - Row-building (pure logic)

@MainActor
struct DiscoveryViewModelRowTests {
    @Test func liveOnlyProducesAvailableRow() {
        let live = DiscoveredTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", udn: "uuid:abc")
        let rows = DiscoveryViewModel.makeRows(live: [live], remembered: [])
        #expect(rows.count == 1)
        #expect(rows.first?.status == .available)
        #expect(rows.first?.udn == "uuid:abc")
        #expect(rows.first?.ip == "192.168.1.42")
        #expect(rows.first?.mac == nil)
    }

    @Test func rememberedOnlyProducesOffRow() {
        let remembered = RememberedTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", mac: "AA:BB:CC:DD:EE:FF", udn: "uuid:abc")
        let rows = DiscoveryViewModel.makeRows(live: [], remembered: [remembered])
        #expect(rows.count == 1)
        #expect(rows.first?.status == .off)
        #expect(rows.first?.mac == "AA:BB:CC:DD:EE:FF")
    }

    @Test func matchByUDNMergesIntoSingleAvailableRow() {
        let live = DiscoveredTV(ip: "192.168.1.99", friendlyName: "Living Room", modelName: "UN55", udn: "uuid:abc")
        let remembered = RememberedTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", mac: "AA:BB:CC:DD:EE:FF", udn: "uuid:abc")
        // Note: IPs differ (DHCP renewal). UDN match should still merge them.
        let rows = DiscoveryViewModel.makeRows(live: [live], remembered: [remembered])
        #expect(rows.count == 1)
        #expect(rows.first?.status == .available)
        #expect(rows.first?.mac == "AA:BB:CC:DD:EE:FF", "MAC from remembered record should carry over")
    }

    @Test func matchByIPMergesLegacyRecords() {
        // Old record written before discovery knew the UDN.
        let live = DiscoveredTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", udn: "uuid:abc")
        let remembered = RememberedTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", mac: "AA:BB:CC:DD:EE:FF", udn: nil)
        let rows = DiscoveryViewModel.makeRows(live: [live], remembered: [remembered])
        #expect(rows.count == 1)
        #expect(rows.first?.status == .available)
        #expect(rows.first?.mac == "AA:BB:CC:DD:EE:FF")
    }

    @Test func mixedLiveAndOffRowsSortAvailableFirst() {
        let live = DiscoveredTV(ip: "192.168.1.42", friendlyName: "Zebra TV", modelName: "UN55", udn: "uuid:live")
        let off = RememberedTV(ip: "192.168.1.43", friendlyName: "Alpha TV", modelName: "UN55", mac: nil, udn: "uuid:off")
        let rows = DiscoveryViewModel.makeRows(live: [live], remembered: [off])
        #expect(rows.count == 2)
        #expect(rows[0].status == .available, "Available should come first even though Alpha < Zebra")
        #expect(rows[0].friendlyName == "Zebra TV")
        #expect(rows[1].status == .off)
        #expect(rows[1].friendlyName == "Alpha TV")
    }

    @Test func rowsWithSameStatusSortByFriendlyName() {
        let a = DiscoveredTV(ip: "192.168.1.1", friendlyName: "Bedroom", modelName: "X", udn: "uuid:b")
        let b = DiscoveredTV(ip: "192.168.1.2", friendlyName: "Attic", modelName: "X", udn: "uuid:a")
        let c = DiscoveredTV(ip: "192.168.1.3", friendlyName: "Cellar", modelName: "X", udn: "uuid:c")
        let rows = DiscoveryViewModel.makeRows(live: [a, b, c], remembered: [])
        #expect(rows.map(\.friendlyName) == ["Attic", "Bedroom", "Cellar"])
    }

    @Test func dedupesAcrossLiveAndRemembered() {
        let live = DiscoveredTV(ip: "192.168.1.42", friendlyName: "Live", modelName: "UN55", udn: "uuid:abc")
        let remembered = RememberedTV(ip: "192.168.1.42", friendlyName: "Remembered", modelName: "UN55", mac: "AA:BB:CC:DD:EE:FF", udn: "uuid:abc")
        let rows = DiscoveryViewModel.makeRows(live: [live], remembered: [remembered])
        #expect(rows.count == 1)
        #expect(rows.first?.friendlyName == "Live", "Live data wins over remembered when both are present")
    }
}

// MARK: - Full view-model lifecycle

@MainActor
struct DiscoveryViewModelLifecycleTests {
    @Test func startLoadsRememberedAndBeginsScanning() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore([
            RememberedTV(ip: "192.168.1.50", friendlyName: "Guest Room", modelName: "UN55", mac: "AA:BB:CC:DD:EE:FF", udn: nil)
        ])
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store)

        await vm.start()

        #expect(discovery.startCount == 1)
        #expect(vm.rows.count == 1)
        #expect(vm.rows.first?.status == .off)
        #expect(vm.isSearching == true)

        // start() itself stops any previous scan first, so count relative — the user's
        // stop() must add exactly one more.
        let stopsAfterStart = discovery.stopCount
        await vm.stop()
        #expect(discovery.stopCount == stopsAfterStart + 1)
        #expect(vm.isSearching == false)
    }

    @Test func liveDiscoveryUpdatesRows() async throws {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store)

        await vm.start()
        discovery.emit(DiscoveredTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", udn: "uuid:abc"))

        try await waitForCondition { vm.rows.count == 1 }
        #expect(vm.rows.first?.status == .available)
        #expect(vm.rows.first?.udn == "uuid:abc")

        await vm.stop()
    }

    @Test func repeatedDiscoveryOfSameUDNDoesNotDuplicate() async throws {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store)

        await vm.start()
        let tv = DiscoveredTV(ip: "192.168.1.42", friendlyName: "Living Room", modelName: "UN55", udn: "uuid:abc")
        discovery.emit(tv)
        discovery.emit(tv)
        discovery.emit(tv)

        try await waitForCondition { vm.rows.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(vm.rows.count == 1)

        await vm.stop()
    }

    @Test func refreshRestartsScanner() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store)

        await vm.start()
        await vm.refresh()

        #expect(discovery.startCount == 2)
        #expect(discovery.stopCount >= 1)

        await vm.stop()
    }

    @Test func deviceForRowUsesCurrentMode() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store, initialMode: .secure)

        let row = DiscoveryViewModel.Row(
            id: "uuid:abc",
            friendlyName: "Living Room",
            modelName: "UN55",
            ip: "192.168.1.42",
            udn: "uuid:abc",
            mac: nil,
            status: .available
        )
        let device = vm.device(for: row)

        #expect(device.ip == "192.168.1.42")
        #expect(device.mode == .secure)
        #expect(device.name == "Living Room")
    }

    @Test func deviceForRowFallsBackToDefaultNameWhenFriendlyNameIsEmpty() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store)

        let row = DiscoveryViewModel.Row(
            id: "uuid:abc",
            friendlyName: "",
            modelName: "",
            ip: "192.168.1.42",
            udn: nil,
            mac: nil,
            status: .available
        )
        #expect(vm.device(for: row).name == "Samsung TV")
    }

    @Test func wakeSendsMagicPacketAndRestartsScan() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let wake = FakeWakeService()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store, wakeService: wake)

        await vm.start()
        let row = DiscoveryViewModel.Row(
            id: "uuid:abc",
            friendlyName: "Living Room",
            modelName: "UN55",
            ip: "192.168.1.42",
            udn: "uuid:abc",
            mac: "AA:BB:CC:DD:EE:FF",
            status: .off
        )
        await vm.wake(row)

        #expect(wake.calls.count == 1)
        #expect(wake.calls.first?.mac == "AA:BB:CC:DD:EE:FF")
        #expect(wake.calls.first?.ip == "192.168.1.42")
        #expect(discovery.startCount == 2, "Successful wake should trigger a refresh")
        #expect(vm.errorMessage == nil)

        await vm.stop()
    }

    @Test func wakeWithoutMACIsNoop() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let wake = FakeWakeService()
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store, wakeService: wake)

        let row = DiscoveryViewModel.Row(
            id: "uuid:abc",
            friendlyName: "TV",
            modelName: "UN55",
            ip: "192.168.1.42",
            udn: "uuid:abc",
            mac: nil,
            status: .off
        )
        await vm.wake(row)

        #expect(wake.calls.isEmpty)
    }

    @Test func wakeSurfacesErrorMessage() async {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let wake = FakeWakeService()
        wake.setError(TVServiceError.wakeOnLANFailure("boom"))
        let vm = DiscoveryViewModel(discovery: discovery, rememberedStore: store, wakeService: wake)

        let row = DiscoveryViewModel.Row(
            id: "uuid:abc",
            friendlyName: "TV",
            modelName: "UN55",
            ip: "192.168.1.42",
            udn: "uuid:abc",
            mac: "AA:BB:CC:DD:EE:FF",
            status: .off
        )
        await vm.wake(row)

        #expect(vm.errorMessage != nil)
    }

    @Test func emptyStateAppearsAfterDelayWithNoTVs() async throws {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore()
        let vm = DiscoveryViewModel(
            discovery: discovery,
            rememberedStore: store,
            emptyStateDelay: .milliseconds(50)
        )

        await vm.start()
        try await waitForCondition { vm.showEmptyState }
        #expect(vm.showEmptyState == true)

        await vm.stop()
    }

    @Test func emptyStateStaysHiddenWhenRememberedTVsExist() async throws {
        let discovery = FakeDiscoveryService()
        let store = InMemoryRememberedStore([
            RememberedTV(ip: "192.168.1.50", friendlyName: "Guest", modelName: "UN55", mac: nil, udn: nil)
        ])
        let vm = DiscoveryViewModel(
            discovery: discovery,
            rememberedStore: store,
            emptyStateDelay: .milliseconds(50)
        )

        await vm.start()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(vm.showEmptyState == false)

        await vm.stop()
    }
}

// MARK: - Helpers

@MainActor
private func waitForCondition(
    timeout: Duration = .seconds(1),
    condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for condition")
}
