import Foundation
import Network

/// `NWBrowser`-backed mDNS/Bonjour discoverer for Samsung Tizen TVs.
///
/// Tizen TVs advertise the Samsung Multiscreen Framework service (`_samsungmsf._tcp.`) on the
/// local network whenever they're powered on and connected to Wi-Fi. The TXT record carries
/// everything we need to populate a ``DiscoveredTV``:
///
/// - `u`  — the UPnP `UDN` (stable across reboots & DHCP renewals)
/// - `md` — the model string (e.g. `UN55Q60AAF`)
/// - `fn` — the user-assigned friendly name (e.g. `[TV] Samsung Q60A`)
///
/// Browsing mDNS via `NWBrowser` does **not** require the
/// `com.apple.developer.networking.multicast` entitlement — the OS-managed mDNS responder is
/// covered by the standard Local Network permission. The app's `Info.plist` must list the
/// service type under `NSBonjourServices`.
actor BonjourDiscoveryService: TVDiscoveryService {
    private let serviceType: String
    private let queue: DispatchQueue

    private var browser: NWBrowser?
    private var continuation: AsyncStream<DiscoveredTV>.Continuation?
    private var seenIdentifiers: Set<String> = []
    private var resolvers: [NWConnection] = []
    /// Drives the proactive re-query schedule (`+3s`, `+7s`). Cancelled on `stop()`.
    private var requeryTask: Task<Void, Never>?
    /// Set the moment a single browse result arrives. Used to short-circuit the
    /// proactive re-queries — if discovery is already working, restarting the browser
    /// would just churn for no reason.
    private var hasFoundResults: Bool = false
    /// Latches when `NWBrowser` reports `.waiting`, which on iOS almost always means
    /// the Local Network permission prompt is up. The first subsequent `.ready` means
    /// the user just tapped Allow and we should re-issue the PTR query.
    private var hasObservedWaiting: Bool = false

    init(serviceType: String = "_samsungmsf._tcp") {
        self.serviceType = serviceType
        self.queue = DispatchQueue(label: "com.remotetv.bonjour", qos: .utility)
    }

    func discoveries() -> AsyncStream<DiscoveredTV> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
        }
    }

    func start() async {
        await stop()
        seenIdentifiers = []
        hasFoundResults = false
        hasObservedWaiting = false

        // On a fresh install, iOS does not always show the Local Network permission prompt
        // just because `NWBrowser` is browsing — the browser can stay in `.ready` while
        // silently returning zero results. Firing a throwaway UDP "connection" to the mDNS
        // multicast group forces the system to evaluate the permission and surface the
        // prompt immediately, so the user grants access at launch instead of only after they
        // manually connect to a typed-in IP.
        primeLocalNetworkPermission()
        startBrowser()
        scheduleProactiveRequery()
    }

    /// Cancels and re-creates the underlying `NWBrowser`. Used both for the initial
    /// start and for re-querying after a permission grant or empty-result timeout —
    /// `NWBrowser` doesn't auto-reissue mDNS queries when it transitions out of
    /// `.waiting`, so the only way to force a fresh PTR query on the wire is to tear
    /// the browser down and stand a new one up. mDNSResponder treats this as a brand-
    /// new browse and broadcasts again.
    private func startBrowser() {
        browser?.cancel()

        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser

        let resultsBridge = ResultsBridge { [weak self] results in
            guard let self else { return }
            Task { await self.handle(results: results) }
        }
        browser.browseResultsChangedHandler = { results, _ in
            resultsBridge.handle(results)
        }
        let stateBridge = StateBridge { [weak self] state in
            guard let self else { return }
            Task { await self.handleBrowserState(state) }
        }
        browser.stateUpdateHandler = { state in
            stateBridge.handle(state)
        }
        browser.start(queue: queue)
    }

    /// Two-step proactive re-query schedule that fires only when no results have
    /// arrived yet. The fresh-install failure mode is well-defined: `NWBrowser`
    /// transitions to `.waiting` while the Local Network permission prompt is up,
    /// drops the in-flight PTR query, then settles in `.ready` once the user taps
    /// Allow — but it never re-broadcasts. We reissue at `+3s` and `+7s` so a TV
    /// that didn't happen to send an unsolicited announcement during the prompt
    /// window still gets surfaced before the empty-state timer fires.
    private func scheduleProactiveRequery() {
        requeryTask = Task { [weak self] in
            for delay: Duration in [.seconds(3), .seconds(7)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self?.requeryIfEmpty()
            }
        }
    }

    private func requeryIfEmpty() {
        guard !hasFoundResults else { return }
        startBrowser()
    }

    /// Reacts to browser-state transitions to keep discovery alive across the Local
    /// Network permission prompt. iOS reports `.waiting(NWError)` while the prompt is
    /// up, then `.ready` once the user taps Allow — but the original PTR query has
    /// already been swallowed. We latch the `.waiting` observation and force an
    /// immediate re-query on the next `.ready`, which restores discovery without
    /// waiting for the proactive timer.
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .waiting(let error):
            hasObservedWaiting = true
            NSLog("BonjourDiscoveryService browser waiting: \(error.localizedDescription)")
        case .ready:
            if hasObservedWaiting {
                hasObservedWaiting = false
                requeryIfEmpty()
            }
        case .failed(let error):
            // Surfaced via stderr rather than throwing, since the browser continues to
            // live on the actor and callers only observe discoveries through the stream.
            NSLog("BonjourDiscoveryService browser failed: \(error.localizedDescription)")
        default:
            break
        }
    }

    /// Opens a short-lived UDP "connection" to the mDNS multicast address (224.0.0.251:5353)
    /// so iOS surfaces the Local Network permission prompt at launch. The connection is
    /// torn down by ``stop()`` alongside the other resolvers — we only need the initial
    /// outbound attempt for the prompt to fire.
    private func primeLocalNetworkPermission() {
        guard let port = NWEndpoint.Port(rawValue: 5353) else { return }
        let host = NWEndpoint.Host("224.0.0.251")
        let connection = NWConnection(host: host, port: port, using: .udp)
        resolvers.append(connection)
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: queue)
    }

    /// Tears down the browser and cancels any in-flight endpoint resolvers. Keeps the
    /// discovery stream alive so a subsequent ``start()`` resumes emitting onto the same
    /// continuation.
    func stop() async {
        requeryTask?.cancel()
        requeryTask = nil
        browser?.cancel()
        browser = nil
        for resolver in resolvers {
            resolver.cancel()
        }
        resolvers.removeAll()
    }

    // MARK: - Private

    private func handle(results: Set<NWBrowser.Result>) {
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            let identifier = "\(name).\(type).\(domain)"
            guard !seenIdentifiers.contains(identifier) else { continue }
            seenIdentifiers.insert(identifier)
            // Latch so the proactive re-query schedule short-circuits — no need to
            // restart a browser that's actively pulling results.
            hasFoundResults = true

            let metadata = Self.extractMetadata(from: result.metadata, serviceName: name, fallbackIdentifier: identifier)
            resolve(endpoint: result.endpoint, metadata: metadata)
        }
    }

    private func resolve(endpoint: NWEndpoint, metadata: ServiceMetadata) {
        // Samsung's remote-control APIs live on IPv4 — if we hand the websocket an IPv6
        // link-local literal (`fe80::…%en0`) it fails to open the socket, and the TV looks
        // unreachable even though Bonjour found it. Pinning resolution to IPv4 avoids that.
        let parameters = NWParameters.tcp
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        resolvers.append(connection)

        let bridge = ResolveBridge { [weak self] ip in
            guard let self else { return }
            Task { await self.finishResolve(connection: connection, ip: ip, metadata: metadata) }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let ip = Self.extractIP(from: connection.currentPath?.remoteEndpoint) {
                    bridge.fire(ip)
                } else {
                    bridge.fire(nil)
                }
            case .failed, .cancelled:
                bridge.fire(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func finishResolve(connection: NWConnection, ip: String?, metadata: ServiceMetadata) {
        connection.cancel()
        resolvers.removeAll { $0 === connection }
        guard let ip else { return }
        continuation?.yield(DiscoveredTV(
            ip: ip,
            friendlyName: metadata.friendlyName,
            modelName: metadata.modelName,
            udn: metadata.udn
        ))
    }

    /// Parses the TXT record attached to a Bonjour result, falling back to sensible defaults
    /// when a TV doesn't populate every field (older models sometimes omit `md`).
    static func extractMetadata(
        from metadata: NWBrowser.Result.Metadata,
        serviceName: String,
        fallbackIdentifier: String
    ) -> ServiceMetadata {
        var udn: String?
        var friendlyName: String?
        var modelName: String?
        if case let .bonjour(record) = metadata {
            let dictionary = record.dictionary
            udn = dictionary["u"].flatMap(Self.nonEmpty)
            friendlyName = dictionary["fn"].flatMap(Self.nonEmpty)
            modelName = dictionary["md"].flatMap(Self.nonEmpty)
        }
        return ServiceMetadata(
            udn: udn ?? fallbackIdentifier,
            friendlyName: friendlyName ?? serviceName,
            modelName: modelName ?? "Samsung TV"
        )
    }

    private static func nonEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Pulls a dotted-quad (or IPv6 literal) out of a resolved `NWPath` remote endpoint.
    /// Returns `nil` for `.service`, `.url`, or unresolved endpoints — callers treat that as
    /// "resolution failed" and simply drop the result.
    ///
    /// Strips any trailing `%<interface>` scope/zone identifier (e.g. `192.168.1.5%en0`)
    /// that `NW*Address.debugDescription` sometimes appends. A zone makes the string
    /// unusable as a URL host and is unnecessary when the TV is on the same subnet.
    static func extractIP(from endpoint: NWEndpoint?) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        let raw: String
        switch host {
        case let .ipv4(address):
            raw = address.debugDescription
        case let .ipv6(address):
            raw = address.debugDescription
        case let .name(name, _):
            raw = name
        @unknown default:
            return nil
        }
        if let percent = raw.firstIndex(of: "%") {
            return String(raw[..<percent])
        }
        return raw
    }

    struct ServiceMetadata: Sendable, Equatable {
        let udn: String
        let friendlyName: String
        let modelName: String
    }
}

/// Trampolines `NWBrowser`'s non-Sendable results callback onto the actor. Wrapped in a
/// reference type so the capture is a pointer, which satisfies strict-concurrency checking
/// when the closure crosses executors.
private final class ResultsBridge: @unchecked Sendable {
    private let handler: @Sendable (Set<NWBrowser.Result>) -> Void
    init(_ handler: @escaping @Sendable (Set<NWBrowser.Result>) -> Void) { self.handler = handler }
    func handle(_ results: Set<NWBrowser.Result>) { handler(results) }
}

/// Mirrors ``ResultsBridge`` for browser state-change callbacks. Lets the actor
/// observe permission-related state transitions (`.waiting` → `.ready`) without
/// crossing executors with a non-Sendable closure.
private final class StateBridge: @unchecked Sendable {
    private let handler: @Sendable (NWBrowser.State) -> Void
    init(_ handler: @escaping @Sendable (NWBrowser.State) -> Void) { self.handler = handler }
    func handle(_ state: NWBrowser.State) { handler(state) }
}

/// Mirrors ``ResultsBridge`` for the single-shot resolve callback.
private final class ResolveBridge: @unchecked Sendable {
    private let handler: @Sendable (String?) -> Void
    private let lock = NSLock()
    private var fired = false
    init(_ handler: @escaping @Sendable (String?) -> Void) { self.handler = handler }
    func fire(_ ip: String?) {
        lock.lock()
        let shouldFire = !fired
        fired = true
        lock.unlock()
        guard shouldFire else { return }
        handler(ip)
    }
}
