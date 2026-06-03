import Foundation
import Observation

/// `URLSessionWebSocketTask`-backed implementation of ``TVService`` for Samsung Tizen TVs.
///
/// Handles the pairing handshake, token persistence, and a transparent one-shot retry when
/// a stored token is rejected — the TV will show its pairing popup again and the user
/// accepts with the physical remote.
@MainActor
@Observable
final class SamsungTVService: TVService {
    private(set) var state: TVConnectionState = .disconnected
    /// Last-known TV power state, derived from periodic `GET /api/v2/` polling while
    /// connected. The WebSocket can stay open while the TV slips into standby, so the
    /// UI uses this to render "connected but TV is off" differently from
    /// "fully connected and on". Resets to ``TVPowerState/unknown`` on disconnect.
    private(set) var tvPowerState: TVPowerState = .unknown
    /// Rolling buffer of control-channel traffic. Bounded to ``sniffLogLimit`` entries.
    private(set) var sniffLog: [SniffLogEntry] = []
    private let sniffLogLimit = 300

    private let tokenStore: any TVTokenStore
    private let rememberedTVsStore: (any RememberedTVsStore)?
    private let deviceInfoService: SamsungDeviceInfoService?
    /// How often the REST info endpoint is polled while connected. Short enough to
    /// feel snappy when the user uses the physical remote to standby/wake the TV,
    /// long enough not to flood the TV's tiny HTTP server.
    private let infoPollInterval: Duration = .seconds(6)
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var infoPollTask: Task<Void, Never>?
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
    /// Resumed when the TV reports `ms.voiceApp.recording` after we open Bixby.
    /// Only one voice session is in flight at a time, so a single optional suffices.
    private var voiceRecordingWaiter: CheckedContinuation<Void, Error>?
    /// Count of audio chunks sent in the current voice session — for console diagnosis.
    private var voiceChunkCount = 0

    init(
        tokenStore: any TVTokenStore,
        rememberedTVsStore: (any RememberedTVsStore)? = nil,
        deviceInfoService: SamsungDeviceInfoService? = nil
    ) {
        self.tokenStore = tokenStore
        self.rememberedTVsStore = rememberedTVsStore
        self.deviceInfoService = deviceInfoService
    }

    func connect(to device: TVDevice) async throws {
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
            try await performHandshake(device: device, token: storedToken, mac: mac)
        } catch TVServiceError.tokenRejected where storedToken != nil {
            // Stored token was stale — wipe under every key it was written
            // under (IP + MAC) and re-pair. Re-resolve MAC fresh from the
            // wire on the retry: if the IP got recycled to a *different* TV
            // (rare but possible), the cached MAC would mis-bind the new
            // pairing.
            await deleteToken(for: device, mac: mac)
            let retryMAC = await freshMAC(for: device) ?? mac
            do {
                try await performHandshake(device: device, token: nil, mac: retryMAC)
            } catch {
                state = .failed(mapError(error))
                throw error
            }
        } catch {
            state = .failed(mapError(error))
            throw error
        }
    }

    func send(_ command: TVCommand) async throws {
        try await transmit(TVCommandEncoder.payload(for: command))
    }

    func sendText(_ string: String) async throws {
        // Readable marker first: the wire frame base64-encodes the text, so without
        // this the log shows an opaque blob. If this line appears but no outbound
        // frame follows, the socket was already gone when we tried to type (e.g. the
        // TV closed the remote channel when Bixby took focus).
        appendSniff(.info, "typing text: \"\(string)\"")
        try await transmit(TVCommandEncoder.textPayload(for: string))
    }

    func sendRawKey(_ keyCode: String, hold: Bool) async throws {
        if hold {
            try await transmit(TVCommandEncoder.rawKeyPayload(keyCode: keyCode, cmd: "Press"))
            try await Task.sleep(for: .milliseconds(700))
            try await transmit(TVCommandEncoder.rawKeyPayload(keyCode: keyCode, cmd: "Release"))
        } else {
            try await transmit(TVCommandEncoder.rawKeyPayload(keyCode: keyCode))
        }
    }

    /// Sends one already-encoded control frame over the live socket and mirrors it
    /// into the sniff log. Shared by ``send(_:)``, ``sendText(_:)``, and
    /// ``sendRawKey(_:hold:)`` so they all guard, log, and transmit identically.
    private func transmit(_ data: Data) async throws {
        guard state == .connected, let task = webSocketTask else {
            throw TVServiceError.notConnected
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TVServiceError.webSocketFailure("Could not encode payload as UTF-8")
        }
        appendSniff(.outbound, text)
        try await task.send(.string(text))
    }

    // MARK: - Voice (Bixby) streaming — see Bixby.md

    /// How long to wait for the TV's `ms.voiceApp.recording` after opening Bixby.
    private let voiceRecordingTimeout: Duration = .seconds(4)

    func beginVoiceSession() async throws {
        guard state == .connected, webSocketTask != nil else {
            throw TVServiceError.notConnected
        }
        // Step 1: toggle the voice key on (Press then Release, back-to-back).
        voiceChunkCount = 0
        // Hold-to-talk: send only the Press here and KEEP it held while audio streams —
        // this firmware treats an immediate Release as "mic button let go" and closes
        // Bixby right after it opens. The matching Release is sent in endVoiceSession().
        try await transmit(TVCommandEncoder.voiceKeyPayload(cmd: "Press"))
        appendSniff(.info, "voice: opening Bixby, waiting for recording…")
        // Step 2: block until the TV says it's listening.
        do {
            try await awaitVoiceRecording()
        } catch {
            // Don't leave the voice key stuck "held" if Bixby never came up.
            try? await transmit(TVCommandEncoder.voiceKeyPayload(cmd: "Release"))
            throw error
        }
        appendSniff(.info, "voice: TV is recording")
    }

    func sendVoiceChunk(_ pcm: Data) async throws {
        guard state == .connected, let task = webSocketTask else {
            throw TVServiceError.notConnected
        }
        // Step 3: one binary frame per chunk.
        let frame = TVCommandEncoder.voiceAudioFrame(pcm: pcm)
        try await task.send(.data(frame))
        voiceChunkCount += 1
        appendSniff(.outbound, "voice audio chunk #\(voiceChunkCount): \(pcm.count) PCM bytes (\(frame.count)-byte frame)")
    }

    func endVoiceSession() async {
        guard state == .connected, let task = webSocketTask else { return }
        // Step 4: empty end-of-stream marker, then Release the (held-down) voice key —
        // the Release is what tells Bixby the user "let go" and to process the utterance.
        try? await task.send(.data(TVCommandEncoder.voiceAudioFrame(pcm: Data([0, 0, 0, 0]))))
        try? await transmit(TVCommandEncoder.voiceKeyPayload(cmd: "Release"))
        appendSniff(.info, "voice: end-of-stream marker + Release sent after \(voiceChunkCount) chunks")
    }

    /// Suspends until the receive loop sees `ms.voiceApp.recording`, or throws
    /// ``TVServiceError/voiceNotReady`` after ``voiceRecordingTimeout``. Single-shot:
    /// whichever of event/timeout fires first resumes the continuation and clears it.
    private func awaitVoiceRecording() async throws {
        let timeout = voiceRecordingTimeout
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            voiceRecordingWaiter = cont
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.failVoiceRecordingWaiter()
            }
        }
    }

    private func resumeVoiceRecordingWaiter() {
        voiceRecordingWaiter?.resume()
        voiceRecordingWaiter = nil
    }

    private func failVoiceRecordingWaiter() {
        voiceRecordingWaiter?.resume(throwing: TVServiceError.voiceNotReady)
        voiceRecordingWaiter = nil
    }

    /// Parses an inbound frame for voice lifecycle events and reacts. Called from the
    /// receive loop alongside ``recordInbound(_:)``.
    private func handleVoiceEvent(_ message: URLSessionWebSocketTask.Message) {
        guard let data = messageData(from: message),
              let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data),
              let event = envelope.event else { return }
        switch event {
        case "ms.voiceApp.recording":
            resumeVoiceRecordingWaiter()
        case "ms.voiceApp.hide":
            appendSniff(.info, "voice: TV finished (ms.voiceApp.hide)")
        default:
            break
        }
    }

    func clearSniffLog() {
        sniffLog.removeAll()
    }

    private func appendSniff(_ direction: SniffLogEntry.Direction, _ text: String) {
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
    func launch(appID: String) async throws {
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

        NSLog("[Launch] POST \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                NSLog("[Launch] \(appID): HTTP \(http.statusCode) body=\(body)")
                if !(200..<300).contains(http.statusCode) {
                    throw TVServiceError.appLaunchFailure("HTTP \(http.statusCode)")
                }
            }
        } catch let error as TVServiceError {
            throw error
        } catch {
            NSLog("[Launch] \(appID): error=\(error.localizedDescription)")
            throw TVServiceError.appLaunchFailure(error.localizedDescription)
        }
    }

    /// Probes each ID in ``KnownTVApps/catalog`` via `GET /api/v2/applications/<id>` in
    /// parallel. A 200 means the app is installed; anything else (404, timeout) means it
    /// isn't. The TV's response body usually carries the canonical display name, which we
    /// prefer over the catalog's fallback.
    ///
    /// We'd love to use `ed.installedApp.get` over the WebSocket — it would return the full
    /// list in one round-trip — but recent Tizen firmware silently ignores it on every model
    /// I've tested. This probe is the fallback.
    func requestInstalledApps() async throws -> [InstalledApp] {
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

    func disconnect() async {
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
    func reconnectIfNeeded() async {
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

    /// Sends a single WebSocket ping and returns whether a pong arrived inside the
    /// timeout. We can't trust `URLSessionWebSocketTask.closeCode` alone: it's `.invalid`
    /// for the entire happy-path lifetime and only flips on a clean close, so a TCP
    /// connection silently severed by iOS leaves it stuck at `.invalid`. The ping is
    /// the only way to force a round-trip and learn the truth.
    private func isSocketAlive() async -> Bool {
        guard let task = webSocketTask else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    task.sendPing { error in
                        cont.resume(returning: error == nil)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return false
            }
            let alive = await group.next() ?? false
            group.cancelAll()
            return alive
        }
    }

    func forget(_ device: TVDevice) async {
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
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                throw TVServiceError.webSocketFailure(String(describing: error))
            }
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

    private func messageData(from message: URLSessionWebSocketTask.Message) -> Data? {
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
        tvPowerState = .unknown
        currentToken = nil
        currentMAC = nil
        // Don't leave a voice session waiter suspended across a disconnect.
        failVoiceRecordingWaiter()
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

    private struct EventEnvelope: Decodable {
        let event: String?
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
