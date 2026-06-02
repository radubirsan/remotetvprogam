import Foundation
import Observation

/// Drives ``DiscoveryView``.
///
/// Merges two sources into a single ordered list:
/// - **Live** ``DiscoveredTV`` values streamed from a ``TVDiscoveryService`` (Bonjour).
/// - **Remembered** ``RememberedTV`` records persisted from prior sessions.
///
/// A TV present in both is shown with status `.available`; a remembered TV missing from the
/// live stream is shown `.off` — which, if we have its MAC on file, enables a Wake button.
///
/// Dedupe key: UDN when both sides have it, else the remembered IP. Within each status band
/// rows are sorted by friendly name.
@MainActor
@Observable
final class DiscoveryViewModel {
    // MARK: - Row

    struct Row: Identifiable, Hashable, Sendable {
        enum Status: Sendable, Hashable { case available, off }

        let id: String
        let friendlyName: String
        let modelName: String
        let ip: String
        let udn: String?
        let mac: String?
        let status: Status
    }

    // MARK: - Observable state

    var rows: [Row] = []
    var mode: TVConnectionMode
    var errorMessage: String?
    /// User-typed IP for the manual-connect affordance. Kept on the VM so the text survives
    /// refresh and mode toggles.
    var manualIP: String = ""
    private(set) var isSearching: Bool = false
    /// Set to the row id currently being woken. Used to disable the Wake button while in flight.
    private(set) var wakingRowID: String?
    /// `true` after ~10s of scanning with zero live results *and* zero remembered TVs — gates
    /// the empty-state view.
    private(set) var showEmptyState: Bool = false

    // MARK: - Dependencies

    private let discovery: any TVDiscoveryService
    private let rememberedStore: any RememberedTVsStore
    private let wakeService: (any WakeOnLANService)?
    private let emptyStateDelay: Duration

    // MARK: - Internal state

    private var liveByIP: [String: DiscoveredTV] = [:]
    private var remembered: [RememberedTV] = []
    private var streamTask: Task<Void, Never>?
    private var emptyStateTask: Task<Void, Never>?

    init(
        discovery: any TVDiscoveryService,
        rememberedStore: any RememberedTVsStore,
        wakeService: (any WakeOnLANService)? = nil,
        initialMode: TVConnectionMode = .plain,
        // Bumped from 10s → 15s so the timer sits comfortably past the proactive
        // re-query schedule in BonjourDiscoveryService (last requery at +7s, plus
        // ~1–2s for the TV's PTR/SRV/TXT round-trip and resolve). On a fresh install
        // the user is also reading the Local Network permission prompt during the
        // first few seconds — 10s used to expire while they were still tapping Allow.
        emptyStateDelay: Duration = .seconds(15)
    ) {
        self.discovery = discovery
        self.rememberedStore = rememberedStore
        self.wakeService = wakeService
        self.mode = initialMode
        self.emptyStateDelay = emptyStateDelay
    }

    // MARK: - Lifecycle

    /// Loads remembered TVs and rebuilds rows without starting the Bonjour browser. Used
    /// when the view first appears so the list isn't empty while the user decides whether
    /// to begin a scan.
    func loadRemembered() async {
        remembered = await rememberedStore.all()
        rebuildRows()
    }

    /// Loads remembered records, begins Bonjour scanning, and starts listening to the
    /// discovery stream. Safe to call repeatedly; each call stops the previous scan first.
    func start() async {
        await stop()
        isSearching = true
        showEmptyState = false
        errorMessage = nil
        liveByIP = [:]
        remembered = await rememberedStore.all()
        rebuildRows()

        let stream = await discovery.discoveries()
        await discovery.start()

        streamTask = Task { [weak self] in
            for await tv in stream {
                guard !Task.isCancelled else { return }
                self?.didDiscover(tv)
            }
        }

        let delay = emptyStateDelay
        emptyStateTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.evaluateEmptyState()
        }
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        emptyStateTask?.cancel()
        emptyStateTask = nil
        await discovery.stop()
        isSearching = false
    }

    /// Dismisses the empty-state view without touching the running scan. Lets the user
    /// return to the main list (manual IP, mode picker, Search/Stop toolbar) after the
    /// 10-second no-results timer has fired.
    func dismissEmptyState() {
        showEmptyState = false
    }

    /// Reruns the scan from scratch. Used by the Refresh toolbar button and by ``wake(_:)``
    /// after a successful magic-packet send.
    func refresh() async {
        await start()
    }

    // MARK: - Row actions

    /// Builds the ``TVDevice`` a `NavigationLink` should push when the user taps a row. Pure
    /// because `NavigationLink(value:)` drives the navigation stack directly — no need for the
    /// VM to manipulate `path`.
    func device(for row: Row) -> TVDevice {
        TVDevice(
            ip: row.ip,
            name: row.friendlyName.isEmpty ? "Samsung TV" : row.friendlyName,
            mode: mode,
            // Carry the MAC (donated by a matched remembered record) so the service can
            // resolve the pairing token by MAC even if DHCP gave the TV a new IP.
            mac: row.mac
        )
    }

    /// Builds a ``TVDevice`` from the manual-IP field. Returns `nil` when the field
    /// is empty; formal IP-format validation is left to ``TVURLBuilder``. An existing
    /// remembered name is reused when we have one on file so the title reads nicely.
    /// The view passes the result up to the root, which flips its `@AppStorage` slot
    /// and the app re-renders into the remote screen — no navigation push.
    func makeManualDevice() -> TVDevice? {
        let trimmed = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let record = remembered.first { $0.ip == trimmed }
        let name = record?.friendlyName ?? "Samsung TV"
        return TVDevice(ip: trimmed, name: name, mode: mode, mac: record?.mac)
    }

    /// Sends a Wake-on-LAN magic packet for a remembered, currently-off TV, then restarts
    /// the scan so the row transitions to `.available` once the TV reattaches to Wi-Fi.
    func wake(_ row: Row) async {
        guard let wakeService, row.status == .off, let mac = row.mac else { return }
        wakingRowID = row.id
        defer { wakingRowID = nil }
        do {
            try await wakeService.wake(mac: mac, ip: row.ip)
            await refresh()
        } catch let error as TVServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func didDiscover(_ tv: DiscoveredTV) {
        liveByIP[tv.ip] = tv
        showEmptyState = false
        rebuildRows()
    }

    private func rebuildRows() {
        rows = Self.makeRows(live: Array(liveByIP.values), remembered: remembered)
    }

    /// Pure merge used by ``rebuildRows()``. Factored out so tests can exercise the dedupe +
    /// ordering logic without spinning up any async plumbing.
    ///
    /// Rules:
    /// - Live entries always become `.available` rows.
    /// - A remembered record "matches" a live entry by `udn` first, then by `ip` (legacy records
    ///   written before discovery knew the UDN). Matched records donate their `mac` but don't
    ///   produce their own row.
    /// - Unmatched remembered records become `.off` rows, enabling the Wake action when `mac`
    ///   is present.
    /// - `.available` rows sort above `.off`; within each band, friendly-name ascending.
    static func makeRows(live: [DiscoveredTV], remembered: [RememberedTV]) -> [Row] {
        var merged: [Row] = []
        var consumedRememberedIPs: Set<String> = []

        for tv in live {
            let match = remembered.first { $0.udn == tv.udn || $0.ip == tv.ip }
            if let match {
                consumedRememberedIPs.insert(match.ip)
            }
            merged.append(Row(
                id: tv.udn,
                friendlyName: tv.friendlyName,
                modelName: tv.modelName,
                ip: tv.ip,
                udn: tv.udn,
                mac: match?.mac,
                status: .available
            ))
        }

        for record in remembered where !consumedRememberedIPs.contains(record.ip) {
            merged.append(Row(
                id: record.udn ?? "ip:\(record.ip)",
                friendlyName: record.friendlyName.isEmpty ? record.ip : record.friendlyName,
                modelName: record.modelName,
                ip: record.ip,
                udn: record.udn,
                mac: record.mac,
                status: .off
            ))
        }

        merged.sort { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .available
            }
            return lhs.friendlyName.localizedStandardCompare(rhs.friendlyName) == .orderedAscending
        }
        return merged
    }

    private func evaluateEmptyState() {
        if liveByIP.isEmpty && remembered.isEmpty {
            showEmptyState = true
        }
    }
}
