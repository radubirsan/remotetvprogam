import Foundation
import Observation

/// `URLSessionWebSocketTask`-backed implementation of ``TVService`` for Samsung Tizen TVs.
///
/// Handles the pairing handshake, token persistence, and a transparent one-shot retry when
/// a stored token is rejected — the TV will show its pairing popup again and the user
/// accepts with the physical remote.
@MainActor
@Observable
public final class SamsungTVService: TVService {
    public private(set) var state: TVConnectionState = .disconnected
    /// Last-known TV power state, derived from periodic `GET /api/v2/` polling while
    /// connected. The WebSocket can stay open while the TV slips into standby, so the
    /// UI uses this to render "connected but TV is off" differently from
    /// "fully connected and on". Resets to ``TVPowerState/unknown`` on disconnect.
    public private(set) var tvPowerState: TVPowerState = .unknown
    /// Rolling buffer of control-channel traffic. Bounded to ``sniffLogLimit`` entries.
    public private(set) var sniffLog: [SniffLogEntry] = []
    private let sniffLogLimit = 300

    private let tokenStore: any TVTokenStore
    private let rememberedTVsStore: (any RememberedTVsStore)?
    private let deviceInfoService: SamsungDeviceInfoService?
    /// How often the REST info endpoint is polled while connected. Short enough to
    /// feel snappy when the user uses the physical remote to standby/wake the TV,
    /// long enough not to flood the TV's tiny HTTP server.
    private let infoPollInterval: Duration = .seconds(6)
    /// How often the foreground heartbeat pings the socket to keep it warm and catch a
    /// silently-dropped connection before the user presses a button.
    private let heartbeatInterval: Duration = .seconds(15)
    private var session: URLSession?
    /// Internal (not private) so the voice extension in `SamsungTVService+Voice.swift`
    /// can stream binary frames over the live socket.
    var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var infoPollTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var trustDelegate: SamsungTrustDelegate?
    private var currentDevice: TVDevice?
    /// The token that authenticated the live socket, and the MAC we've already
    /// written it under. Retained so the info-poll can *back-fill* the MAC-keyed
    /// Keychain slot the moment it learns the MAC — without this, a pairing where
    /// the MAC wasn't yet known (REST info server slow to come up right after
    /// power-on) would leave the token under the IP key only, and the next DHCP
    /// rotation would strand it and re-prompt for pairing. `nil` while disconnected.
    private var currentToken: String?
    private var currentMAC: String?
    // Voice-session state. Stored here because extensions can't add stored instance
    // properties; every method that touches these lives in `SamsungTVService+Voice.swift`
    // (which is also why they're internal rather than private).
    /// Resumed when the TV reports `ms.voiceApp.recording` after we open Bixby.
    /// Only one voice session is in flight at a time, so a single optional suffices.
    var voiceRecordingWaiter: CheckedContinuation<Void, Error>?
    /// Count of audio chunks sent in the current voice session — for console diagnosis.
    var voiceChunkCount = 0
    /// True from the moment a voice session opens until it ends. The heartbeat checks this so
    /// a stray keepalive ping/reconnect can't tear Bixby down mid-utterance.
    var voiceSessionActive = false

    public init(
        tokenStore: any TVTokenStore,
        rememberedTVsStore: (any RememberedTVsStore)? = nil,
        deviceInfoService: SamsungDeviceInfoService? = nil
    ) {
        self.tokenStore = tokenStore
        self.rememberedTVsStore = rememberedTVsStore
        self.deviceInfoService = deviceInfoService
    }

    public func connect(to device: TVDevice) async throws {
        await teardown()
        currentDevice = device
        state = .connecting
        appendSniff(.info, "connect \(device.ip) mode=\(device.mode)")

        // Resolve the token *and* the TV's MAC up-front so both the in-flight
        // handshake and the post-success save use a DHCP-rotation-proof key.
        // Without this, every router lease change re-prompted the user for
        // pairing on the physical remote — the IP-keyed token in Keychain
        // looked up against the new IP would miss and we'd open the socket
        // with no token at all.
        let (storedToken, mac) = await resolveStoredToken(for: device)

        do {
            try await handshakeWithRetry(device: device, token: storedToken, mac: mac)
        } catch TVServiceError.tokenRejected where storedToken != nil {
            // Stored token was stale — wipe under every key it was written
            // under (IP + MAC) and re-pair. Re-resolve MAC fresh from the
            // wire on the retry: if the IP got recycled to a *different* TV
            // (rare but possible), the cached MAC would mis-bind the new
            // pairing.
            await deleteToken(for: device, mac: mac)
            let retryMAC = await freshMAC(for: device) ?? mac
            do {
                try await handshakeWithRetry(device: device, token: nil, mac: retryMAC)
            } catch {
                state = .failed(mapError(error))
                throw error
            }
        } catch {
            state = .failed(mapError(error))
            throw error
        }
    }

    /// Runs the handshake, retrying a few times on *transient* network failures. At cold
    /// launch the WebSocket can fire microseconds before iOS has brought the local-network
    /// path up, failing instantly with `-1009`/`ENETDOWN` — which left the status indicator
    /// grey until the user relaunched (the "every second run" bug). Token/auth failures are
    /// **not** retried here: they propagate so `connect()`'s re-pair path handles them.
    private func handshakeWithRetry(device: TVDevice, token: String?, mac: String?) async throws {
        let maxAttempts = 4
        var attempt = 1
        while true {
            do {
                try await performHandshake(device: device, token: token, mac: mac)
                return
            } catch let error where attempt < maxAttempts && Self.isTransientNetworkError(error) {
                appendSniff(.info, "connect attempt \(attempt) failed (network not ready) — retrying")
                await teardown()
                state = .connecting
                try? await Task.sleep(for: .milliseconds(600))
                attempt += 1
            }
        }
    }

    /// True for errors that mean "the network path wasn't ready", not "the TV said no".
    /// These are worth a quick retry; auth/protocol failures (which arrive as
    /// ``TVServiceError``, not `URLError`) are not and fall through to `.failed`.
    /// `nonisolated` because it's a pure classification — also lets tests call it directly.
    nonisolated static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,   // -1009 — ENETDOWN, the launch-race symptom
             .networkConnectionLost,    // -1005
             .cannotConnectToHost,      // -1004 — TV NIC still coming up
             .timedOut,                 // -1001
             .cannotFindHost:           // -1003
            return true
        default:
            return false
        }
    }

    public func send(_ command: TVCommand) async throws {
        try await transmit(TVCommandEncoder.payload(for: command))
    }

    public func sendText(_ string: String) async throws {
        // Readable marker first: the wire frame base64-encodes the text, so without
        // this the log shows an opaque blob. If this line appears but no outbound
        // frame follows, the socket was already gone when we tried to type (e.g. the
        // TV closed the remote channel when Bixby took focus).
        appendSniff(.info, "typing text: \"\(string)\"")
        try await transmit(TVCommandEncoder.textPayload(for: string))
    }

    public func sendRawKey(_ keyCode: String, hold: Bool) async throws {
        if hold {
            try await transmit(TVCommandEncoder.rawKeyPayload(keyCode: keyCode, cmd: "Press"))
            try await Task.sleep(for: .milliseconds(700))
            try await transmit(TVCommandEncoder.rawKeyPayload(keyCode: keyCode, cmd: "Release"))
        } else {
            try await transmit(TVCommandEncoder.rawKeyPayload(keyCode: keyCode))
        }
    }

    /// Sends one already-encoded control frame over the live socket and mirrors it
    /// into the sniff log. Shared by ``send(_:)``, ``sendText(_:)``,
    /// ``sendRawKey(_:hold:)``, and the voice extension so they all guard, log, and
    /// transmit identically.
    func transmit(_ data: Data) async throws {
        guard state == .connected, let task = webSocketTask else {
            throw TVServiceError.notConnected
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TVServiceError.webSocketFailure("Could not encode payload as UTF-8")
        }
        appendSniff(.outbound, text)
        try await task.send(.string(text))
    }

    // Voice (Bixby) streaming lives in `SamsungTVService+Voice.swift` — see Bixby.md.

    public func clearSniffLog() {
        sniffLog.removeAll()
    }

    func appendSniff(_ direction: SniffLogEntry.Direction, _ text: String) {
        sniffLog.append(SniffLogEntry(direction: direction, text: text))
        if sniffLog.count > sniffLogLimit {
            sniffLog.removeFirst(sniffLog.count - sniffLogLimit)
        }
        // Mirror to the Xcode console so logs can be copy-pasted for diagnosis.
        let tag: String
        switch direction {
        case .inbound:  tag = "<-"
        case .outbound: tag = "->"
        case .info:     tag = " ."
        }
        print("[RemoteTV] \(tag) \(text)")
    }

    private func recordInbound(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            appendSniff(.inbound, text)
        case .data(let data):
            let text = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            appendSniff(.inbound, text)
        @unknown default:
            appendSniff(.inbound, "<unknown message type>")
        }
    }

    /// Launches a Tizen app by POSTing to `http://<ip>:8001/api/v2/applications/<appId>`.
    ///
    /// The WebSocket path (`ms.channel.emit` + `ed.apps.launch`) is documented but silently
    /// fails on a lot of current Tizen builds — the TV accepts the frame and does nothing.
    /// The REST endpoint is what Samsung SmartThings uses, and it works across every 2019+
    /// model I've tested against. HTTP on port 8001 is reachable regardless of whether the
    /// remote-control channel is plain or secure.
    public func launch(appID: String) async throws {
        guard state == .connected, let device = currentDevice else {
            throw TVServiceError.notConnected
        }
        guard
            let encoded = appID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "http://\(device.ip):8001/api/v2/applications/\(encoded)")
        else {
            throw TVServiceError.appLaunchFailure("Could not build launch URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5

        appendSniff(.outbound, "launch POST \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                appendSniff(.inbound, "launch \(appID): HTTP \(http.statusCode) body=\(body)")
                if !(200..<300).contains(http.statusCode) {
                    throw TVServiceError.appLaunchFailure("HTTP \(http.statusCode)")
                }
            }
        } catch let error as TVServiceError {
            throw error
        } catch {
            appendSniff(.info, "launch \(appID): error=\(error.localizedDescription)")
            throw TVServiceError.appLaunchFailure(error.localizedDescription)
        }
    }

    /// Candidate DIAL "Application-URL" bases for Samsung TVs, most-likely first. The real
    /// base is normally discovered via SSDP (the `Application-URL` response header on the
    /// device-description fetch), but SSDP is deliberately *not* used in this app — it forces
    /// the multicast entitlement and was ripped out of discovery. So instead we probe the
    /// handful of bases Samsung has actually shipped, GETting `<base>/YouTube` until one
    /// returns the app-state document:
    ///   * `:8080/ws/app/`  — singular "app", port 8080 (common on 2018–2021 Tizen; the one
    ///                        that answers on our test set)
    ///   * `/ws/app/`       — singular, port 80 (some firmware / reverse-engineering writeups)
    ///   * `:8080/ws/apps/` — plural, port 8080 (textbook DIAL path; some firmware)
    /// Used only for the screenId state GET now — YouTube is foregrounded via the plain
    /// app-launch REST, not DIAL, to avoid triggering Samsung Multi View.
    private func dialBaseURLs(ip: String) -> [String] {
        [
            "http://\(ip):8080/ws/app",
            "http://\(ip)/ws/app",
            "http://\(ip):8080/ws/apps",
        ]
    }

    /// Casts a specific YouTube video (optionally a playlist + start offset) to the TV's
    /// YouTube app, the way Chromecast and the phone app do it:
    ///   1. DIAL-launch YouTube (opens the app, satisfies the Origin/CSRF check).
    ///   2. Read the `screenId` the app publishes in its DIAL `additionalData`.
    ///   3. Drive playback over the private YouTube **Lounge** API (token → bind → setPlaylist).
    ///
    /// The Lounge API is undocumented and can break if Google changes it. Every stage logs to
    /// the sniff log so a failure points at exactly which step broke.
    public func castYouTubeVideo(videoId: String, listId: String?, startSeconds: Int) async throws {
        guard state == .connected, currentDevice != nil else {
            throw TVServiceError.notConnected
        }

        // Foreground YouTube via the plain REST **app-launch** (port 8001), NOT a DIAL launch.
        // On these Samsung sets a DIAL "cast" launch that arrives while another source (live TV,
        // Netflix) is active makes the TV pop **Multi View** — YouTube and the old source side
        // by side. The normal app-launch opens YouTube fullscreen, single-view, with no cast
        // semantics; Lounge then plays the video inside that already-foreground app. (The
        // screenId still comes from the DIAL *state* document below — a GET, which doesn't
        // trigger Multi View.)
        try await launch(appID: TVApp.youtube.appID)

        let screenId = try await fetchYouTubeScreenId()

        appendSniff(.info, "Lounge: connecting (screenId=\(screenId.prefix(12))…)")
        let client = YouTubeLoungeClient(senderName: "RemoteTV")
        do {
            try await client.play(screenId: screenId, videoId: videoId, listId: listId, startSeconds: startSeconds)
            appendSniff(.info, "Lounge: setPlaylist sent (v=\(videoId), t=\(startSeconds))")
        } catch {
            appendSniff(.info, "Lounge error: \(error)")
            throw TVServiceError.appLaunchFailure("Lounge: \(error)")
        }
    }

    /// Reads the YouTube app's `screenId` from its DIAL `<additionalData>`. YouTube registers
    /// its screen with the TV's DIAL/MDX service whenever it's running, regardless of how it
    /// was launched — so we just GET the DIAL state document (across the candidate bases) and
    /// scrape the id. The app populates it a beat after launch, so we poll. GET is sent
    /// *without* an Origin header — only state-changing POSTs are CSRF-gated, and a stray
    /// Origin could itself trip a 403.
    private func fetchYouTubeScreenId() async throws -> String {
        guard let device = currentDevice else { throw TVServiceError.notConnected }
        let bases = dialBaseURLs(ip: device.ip)
        for attempt in 1...10 {
            for base in bases {
                guard let url = URL(string: "\(base)/YouTube") else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 4
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let xml = String(data: data, encoding: .utf8) {
                    if let screenId = firstRegexMatch(in: xml, pattern: "<screenId>([^<]+)</screenId>") {
                        appendSniff(.inbound, "DIAL YouTube screenId=\(screenId)")
                        return screenId
                    }
                    if attempt == 1 {
                        appendSniff(.inbound, "DIAL YouTube state (no screenId yet): \(xml.prefix(220))")
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(800))
        }
        throw TVServiceError.appLaunchFailure("No YouTube screenId in DIAL additionalData")
    }

    /// Probes each ID in ``KnownTVApps/catalog`` via `GET /api/v2/applications/<id>` in
    /// parallel. A 200 means the app is installed; anything else (404, timeout) means it
    /// isn't. The TV's response body usually carries the canonical display name, which we
    /// prefer over the catalog's fallback.
    ///
    /// We'd love to use `ed.installedApp.get` over the WebSocket — it would return the full
    /// list in one round-trip — but recent Tizen firmware silently ignores it on every model
    /// I've tested. This probe is the fallback.
    public func requestInstalledApps() async throws -> [InstalledApp] {
        guard state == .connected, let device = currentDevice else {
            throw TVServiceError.notConnected
        }
        let ip = device.ip

        let installed = await withTaskGroup(of: InstalledApp?.self) { group in
            for probe in KnownTVApps.catalog {
                group.addTask {
                    await Self.probe(ip: ip, appID: probe.appID, fallbackName: probe.fallbackName)
                }
            }
            var results: [InstalledApp] = []
            for await app in group {
                if let app { results.append(app) }
            }
            return results
        }

        // Collapse entries that resolve to the same display name — the catalog probes
        // multiple IDs for a few rebranded apps (HBO Go / HBO Max / Max), and we don't want
        // two buttons if both IDs happen to be installed.
        var seen: Set<String> = []
        let unique = installed.filter { seen.insert($0.name.lowercased()).inserted }
        return unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func probe(ip: String, appID: String, fallbackName: String) async -> InstalledApp? {
        guard let url = URL(string: "http://\(ip):8001/api/v2/applications/\(appID)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            return nil
        }

        if
            let info = try? JSONDecoder().decode(AppInfo.self, from: data),
            let name = info.name, !name.isEmpty
        {
            return InstalledApp(appID: appID, name: name)
        }
        return InstalledApp(appID: appID, name: fallbackName)
    }

    public func disconnect() async {
        appendSniff(.info, "disconnect")
        await teardown()
        currentDevice = nil
        state = .disconnected
    }

    /// Recovery hook for foregrounding. The receive loop is parked on
    /// `URLSessionWebSocketTask.receive()` while the app is suspended; iOS routinely
    /// kills the underlying TCP connection for backgrounded apps, but the parked read
    /// only surfaces the failure on the next system-driven wake — so on resume `state`
    /// can still read `.connected` against an actually-dead socket. We probe with a
    /// WebSocket ping (cheap, racing a 2s timeout) and only re-handshake when the
    /// probe fails or the state machine already shows the connection gone. No-op when
    /// a connect is already in flight or there's no remembered device.
    public func reconnectIfNeeded() async {
        guard let device = currentDevice else { return }

        switch state {
        case .connecting, .awaitingPairing:
            return
        case .connected:
            if await isSocketAlive() { return }
            appendSniff(.info, "ping failed; reconnecting")
        case .disconnected, .failed:
            appendSniff(.info, "auto-reconnect after \(state)")
        }

        try? await connect(to: device)
    }

    private enum PingOutcome { case pong, noAnswer, failed }

    /// Pings the socket and reports one of three outcomes: a pong came back (`pong`); the ping
    /// reported a transport error, i.e. the socket is genuinely broken (`failed`); or neither
    /// happened within `timeout` (`noAnswer`).
    ///
    /// The three-way distinction is load-bearing: **many Samsung TVs never answer WebSocket
    /// pings**, so a `noAnswer` is NOT evidence the socket is dead. Conflating it with `failed`
    /// made the heartbeat reconnect every 15s against a perfectly healthy connection — which
    /// tore down in-flight Bixby voice sessions. We can't trust `closeCode` either: it stays
    /// `.invalid` for the whole happy-path lifetime, so the ping's *error* is the only signal.
    private func pingSocket(timeout: Duration = .seconds(2)) async -> PingOutcome {
        guard let task = webSocketTask else { return .failed }
        return await withTaskGroup(of: PingOutcome.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<PingOutcome, Never>) in
                    task.sendPing { error in
                        cont.resume(returning: error == nil ? .pong : .failed)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .noAnswer
            }
            let outcome = await group.next() ?? .noAnswer
            group.cancelAll()
            return outcome
        }
    }

    /// True only when a pong came back. Used by ``reconnectIfNeeded()`` on foreground resume,
    /// where a reconnect is cheap and expected — so a non-answering TV reconnecting once there
    /// is acceptable (unlike the every-15s heartbeat, which must be stricter).
    private func isSocketAlive() async -> Bool {
        await pingSocket() == .pong
    }

    public func forget(_ device: TVDevice) async {
        // Capture the cached MAC *before* deleting the remembered-TVs record —
        // once it's gone, the MAC-rescue lookup wouldn't find it for the
        // matching `deleteToken` sweep and a stale MAC-keyed token would
        // survive in the Keychain, silently re-authenticating the user on the
        // next connect to the same TV.
        let mac = await cachedMAC(for: device.ip)
        await deleteToken(for: device, mac: mac)
        try? await rememberedTVsStore?.delete(ip: device.ip)
        if currentDevice?.ip == device.ip {
            await disconnect()
        }
    }

    /// Recurring REST info poll. First tick persists a ``RememberedTV`` record (so
    /// Wake-on-LAN works on next launch even before the TV responds again); every
    /// tick refreshes ``tvPowerState`` so the UI can react when the TV slips into
    /// standby while the WebSocket is still nominally up. Best-effort throughout —
    /// transient HTTP failures don't tear down the WebSocket; the next tick covers it.
    private func startInfoPolling(for device: TVDevice) {
        infoPollTask?.cancel()
        infoPollTask = Task { [weak self] in
            var pendingPersist = true
            while !Task.isCancelled {
                await self?.refreshTVInfo(for: device, persistRememberedTV: pendingPersist)
                pendingPersist = false
                try? await Task.sleep(for: self?.infoPollInterval ?? .seconds(6))
            }
        }
    }

    /// Foreground keepalive. Samsung TVs (and NATs in between) silently drop an idle
    /// remote-control socket without sending a close frame, which the parked `receive()`
    /// loop wouldn't notice until the next send — so the first key press after a long idle
    /// would fail. Pinging every ``heartbeatInterval`` keeps the socket warm and, if a pong
    /// doesn't come back, kicks a reconnect *before* the user touches a button.
    ///
    /// The reconnect runs in its own detached `Task` on purpose: `connect()` calls
    /// `teardown()`, which cancels *this* heartbeat task — doing the reconnect inline would
    /// run `connect()` inside a cancelled task and abort its `Task.sleep`/receive mid-flight.
    /// We hand it off and `return`; a successful reconnect starts a fresh heartbeat.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.heartbeatInterval ?? .seconds(15))
                guard let self else { return }
                // Skip while connecting, or while a voice session is live (a reconnect would
                // tear Bixby down mid-utterance).
                guard !Task.isCancelled, self.state == .connected, !self.voiceSessionActive else { continue }
                // Reconnect ONLY on a definite transport error. A missing pong (`noAnswer`) is
                // not proof the socket is dead — many Samsung TVs simply don't answer pings —
                // and reconnecting on it churns the connection every 15s. Genuine death still
                // surfaces via the receive loop and the next send.
                if await self.pingSocket() == .failed, let device = self.currentDevice {
                    self.appendSniff(.info, "heartbeat: socket error — reconnecting")
                    Task { [weak self] in try? await self?.connect(to: device) }
                    return
                }
            }
        }
    }

    private func refreshTVInfo(for device: TVDevice, persistRememberedTV: Bool) async {
        guard let deviceInfoService else { return }
        let info = try? await deviceInfoService.fetch(ip: device.ip)
        if let info {
            tvPowerState = info.powerState
        }
        // Back-fill the MAC-keyed token slot the first time we learn a MAC we haven't
        // already saved the live token under. Closes the gap where the MAC was unknown
        // at handshake (so the token only landed under the IP key) — from here on a
        // DHCP rotation can still recover the token via MAC instead of re-pairing.
        if let mac = info?.wifiMac?.lowercased(), !mac.isEmpty,
           mac != currentMAC, let token = currentToken {
            await saveToken(token, for: device, mac: mac)
            currentMAC = mac
            appendSniff(.info, "back-filled token under MAC \(mac)")
        }
        if persistRememberedTV, let rememberedTVsStore {
            let record = RememberedTV(
                ip: device.ip,
                friendlyName: info?.name ?? device.name,
                modelName: info?.modelName ?? "",
                mac: info?.wifiMac,
                udn: nil
            )
            try? await rememberedTVsStore.upsert(record)
        }
    }

    // MARK: - Handshake

    private func performHandshake(device: TVDevice, token: String?, mac: String?) async throws {
        let url = try TVURLBuilder.connectURL(for: device, token: token)
        let session = makeSession(for: device.mode)
        self.session = session

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        if token == nil {
            state = .awaitingPairing
        }

        let result = try await awaitHandshake(on: task)
        switch result {
        case .connected(let receivedToken):
            // Modern Tizen echoes the token on a fresh pairing but stays
            // silent on token reuse. In both cases the credential we want
            // persisted is "whatever just authenticated this socket" — the
            // echoed token if present, otherwise the one we sent in. We also
            // ignore empty-string echoes so a defensive firmware quirk can't
            // poison the Keychain entry into an unusable empty value.
            let effective = (receivedToken?.isEmpty == false ? receivedToken : nil) ?? token
            if let effective {
                await saveToken(effective, for: device, mac: mac)
            }
            // Retain the live credential so the info-poll can back-fill the MAC slot
            // later if `mac` was nil here (MAC not yet known at handshake time).
            currentToken = effective
            currentMAC = mac
            state = .connected
            startReceiveLoop(on: task)
            startInfoPolling(for: device)
            startHeartbeat()
        case .unauthorized:
            await teardown()
            throw TVServiceError.tokenRejected
        case .rejected:
            await teardown()
            throw TVServiceError.pairingRejected
        case .timeout:
            await teardown()
            throw TVServiceError.pairingTimeout
        }
    }

    // MARK: - Token resolution

    /// Reads the cached MAC for a TV from the remembered-TVs store, normalised
    /// to lowercase. Returns `nil` for "we have no record at this IP" or "the
    /// record has no MAC field yet" (e.g. first-ever connect, before the
    /// info-poll has had a chance to capture it).
    private func cachedMAC(for ip: String) async -> String? {
        guard
            let raw = await rememberedTVsStore?.get(ip: ip)?.mac,
            !raw.isEmpty
        else { return nil }
        return raw.lowercased()
    }

    /// Fetches the TV's MAC straight from the REST info endpoint, bypassing
    /// the cache entirely. Used on the rescue/retry paths where the cached
    /// MAC might be stale (DHCP rotation surfaced a new IP, TV swap on a
    /// recycled IP). Bounded by `SamsungDeviceInfoService.timeout` (3s).
    private func freshMAC(for device: TVDevice) async -> String? {
        guard let deviceInfoService else { return nil }
        guard let info = try? await deviceInfoService.fetch(ip: device.ip) else { return nil }
        guard let mac = info.wifiMac, !mac.isEmpty else { return nil }
        return mac.lowercased()
    }

    /// Cache-first MAC resolution: hits the remembered-TVs store, then falls
    /// back to a REST probe. Used during the rescue path when an IP-keyed
    /// token misses but a MAC-keyed one might still be valid from a previous
    /// DHCP lease. The REST cost is only paid on the rescue path, never on
    /// the steady-state happy path where the IP-keyed token resolves cleanly.
    private func stableMAC(for device: TVDevice) async -> String? {
        if let mac = await cachedMAC(for: device.ip) { return mac }
        return await freshMAC(for: device)
    }

    /// Two-tier token lookup that fixes the "TV re-asks for pairing every
    /// couple of days" failure mode: try the legacy IP key first (cheap, hits
    /// for the common case where DHCP didn't rotate), then rescue via MAC
    /// when it doesn't. The MAC is returned alongside the token so the
    /// post-handshake save can also write under MAC even when the cheap IP
    /// lookup found the token first — without that, the very first IP
    /// rotation after the fix shipped would still strand the user.
    private func resolveStoredToken(for device: TVDevice) async -> (token: String?, mac: String?) {
        // A MAC carried on the device (donated by the remembered-TVs record at
        // discovery time) is the cheapest stable anchor — no Keychain-by-IP miss,
        // no REST probe. Prefer it for the MAC we thread through the save path.
        let carriedMAC = device.mac.flatMap { $0.isEmpty ? nil : $0.lowercased() }

        if let token = await tokenStore.token(for: device.ip), !token.isEmpty {
            if let carriedMAC {
                return (token, carriedMAC)
            }
            return (token, await cachedMAC(for: device.ip))
        }
        // IP slot missed (likely a DHCP rotation). Fall back to the MAC slot, using
        // the carried MAC first and only probing the network if we still don't know it.
        let mac: String?
        if let carriedMAC {
            mac = carriedMAC
        } else {
            mac = await stableMAC(for: device)
        }
        if let mac, let token = await tokenStore.token(for: mac), !token.isEmpty {
            appendSniff(.info, "token resolved via MAC \(mac) (IP changed since pairing)")
            return (token, mac)
        }
        return (nil, mac)
    }

    /// Writes the token under every key we'd later look it up under: the
    /// current IP (legacy slot, also rescues us if MAC capture ever fails)
    /// and the MAC if we know it. Empty tokens are silently ignored — they
    /// can't authenticate but would mask a real saved token on the next
    /// lookup if we let them overwrite a populated slot.
    private func saveToken(_ token: String, for device: TVDevice, mac: String?) async {
        guard !token.isEmpty else { return }
        try? await tokenStore.save(token, for: device.ip)
        if let mac {
            try? await tokenStore.save(token, for: mac)
        }
    }

    /// Drops every key we may have written this device's token under. Run on
    /// both `ms.channel.unauthorized` (TV invalidated the pairing) and
    /// explicit user Forget — without the MAC sweep, a stale MAC-keyed token
    /// would survive the retry and keep getting offered to the TV.
    private func deleteToken(for device: TVDevice, mac: String?) async {
        try? await tokenStore.delete(for: device.ip)
        if let mac {
            try? await tokenStore.delete(for: mac)
        }
    }

    // MARK: - Handshake message loop

    private func awaitHandshake(on task: URLSessionWebSocketTask) async throws -> HandshakeResult {
        while true {
            // Let a receive() failure propagate *raw* (don't stringify it). At cold launch
            // this is typically a transient "network path not ready" error (-1009/ENETDOWN);
            // connect() inspects the URLError code to decide whether to retry. mapError() still
            // turns it into a readable message for the final, give-up case.
            let message = try await task.receive()
            recordInbound(message)
            guard let data = messageData(from: message) else { continue }
            if let result = parseHandshake(data) {
                return result
            }
        }
    }

    private func parseHandshake(_ data: Data) -> HandshakeResult? {
        guard let envelope = try? JSONDecoder().decode(ConnectEnvelope.self, from: data) else {
            return nil
        }
        switch envelope.event {
        case "ms.channel.connect":
            return .connected(token: envelope.data?.token)
        case "ms.channel.unauthorized":
            return .unauthorized
        case "ms.channel.timeOut":
            return .timeout
        case "ms.channel.clientDisconnect":
            return .rejected
        default:
            return nil
        }
    }

    func messageData(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .data(let data): data
        case .string(let text): Data(text.utf8)
        @unknown default: nil
        }
    }

    // MARK: - Session

    private func makeSession(for mode: TVConnectionMode) -> URLSession {
        switch mode {
        case .plain:
            return URLSession(configuration: .default)
        case .secure:
            let delegate = SamsungTrustDelegate()
            trustDelegate = delegate
            return URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
        }
    }

    private func startReceiveLoop(on task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    self?.recordInbound(message)
                    self?.handleVoiceEvent(message)
                } catch {
                    if Task.isCancelled { return }
                    self?.handleReceiveTermination(task: task, error: error)
                    return
                }
            }
        }
    }

    /// Differentiates a clean WebSocket close (TV powered off, app backgrounded long
    /// enough that the TV ended the session) from an actual transport failure. A
    /// normal close drops us to ``TVConnectionState/disconnected`` and clears the
    /// power state so the LED reverts to grey rather than glaring red. Anything else
    /// falls through to ``TVConnectionState/failed`` so the user can retry / repair.
    private func handleReceiveTermination(task: URLSessionWebSocketTask, error: Error) {
        let code = task.closeCode
        let normal = code == .normalClosure || code == .goingAway
        appendSniff(.info, "ws closed code=\(code.rawValue) normal=\(normal)")
        infoPollTask?.cancel()
        infoPollTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        tvPowerState = .unknown
        if normal {
            state = .disconnected
        } else {
            state = .failed(mapError(error))
        }
    }

    private func teardown() async {
        receiveTask?.cancel()
        receiveTask = nil
        infoPollTask?.cancel()
        infoPollTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        tvPowerState = .unknown
        currentToken = nil
        currentMAC = nil
        // Don't leave a voice session waiter suspended across a disconnect.
        failVoiceRecordingWaiter()
        voiceSessionActive = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        trustDelegate = nil
    }

    private func mapError(_ error: Error) -> TVServiceError {
        if let svc = error as? TVServiceError { return svc }
        return .webSocketFailure(String(describing: error))
    }

    private enum HandshakeResult {
        case connected(token: String?)
        case unauthorized
        case rejected
        case timeout
    }

    private struct ConnectEnvelope: Decodable {
        let event: String
        let data: EnvelopeData?

        struct EnvelopeData: Decodable {
            let token: String?
        }
    }

    private struct AppInfo: Decodable {
        let name: String?
    }
}
