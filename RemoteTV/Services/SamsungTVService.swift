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

        let storedToken = await tokenStore.token(for: device.ip)

        do {
            try await performHandshake(device: device, token: storedToken)
        } catch TVServiceError.tokenRejected where storedToken != nil {
            // Stored token was stale — drop it and re-pair once.
            try? await tokenStore.delete(for: device.ip)
            do {
                try await performHandshake(device: device, token: nil)
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
        guard state == .connected, let task = webSocketTask else {
            throw TVServiceError.notConnected
        }
        let data = try TVCommandEncoder.payload(for: command)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TVServiceError.webSocketFailure("Could not encode payload as UTF-8")
        }
        appendSniff(.outbound, text)
        try await task.send(.string(text))
    }

    func clearSniffLog() {
        sniffLog.removeAll()
    }

    private func appendSniff(_ direction: SniffLogEntry.Direction, _ text: String) {
        sniffLog.append(SniffLogEntry(direction: direction, text: text))
        if sniffLog.count > sniffLogLimit {
            sniffLog.removeFirst(sniffLog.count - sniffLogLimit)
        }
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

    func forget(_ device: TVDevice) async {
        try? await tokenStore.delete(for: device.ip)
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

    private func performHandshake(device: TVDevice, token: String?) async throws {
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
            if let receivedToken {
                try? await tokenStore.save(receivedToken, for: device.ip)
            }
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
