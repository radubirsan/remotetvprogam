import Foundation
import Observation
import RemoteTVCore

/// What happened the last time the user pressed the power button while the
/// view model was in "wake" mode. Surfaced on `RemoteViewModel.lastError` for the
/// non-`.sent` cases so the UI's existing error path can render the message.
enum RemoteWakeOutcome: Equatable, Sendable {
    /// Magic packet was dispatched (delivery is best-effort — UDP, no ack).
    case sent
    /// We don't have the TV's MAC on file yet; user must connect once with the TV
    /// awake so the app can capture it via the REST info endpoint.
    case macUnknown
    /// No wake service was injected — composition error in the host app.
    case wakeServiceMissing
    /// The wake service threw — usually a network failure (Wi-Fi dropped, etc.).
    case failed(String)
}

@MainActor
@Observable
final class RemoteViewModel {
    let device: TVDevice
    let service: any TVService
    private(set) var lastError: String?
    /// The app's tracked mute state — `true` once we've muted the TV, `false` once unmuted.
    /// Tizen never reports mute over the socket, so this reflects our own intent; the
    /// deterministic volume-nudge mute/unmute keeps it honest even if someone uses the
    /// physical remote. Drives the Mute button's filled state and whether the central area
    /// shows the auto-unmute scheduler.
    private(set) var isMuted: Bool = false
    /// Non-nil while an auto-unmute countdown is running. Drives the toolbar countdown + the
    /// in-remote scheduler dial.
    private(set) var commercialMuteRemaining: Duration?
    /// Total seconds of the running countdown — lets the scheduler dial draw an accurate
    /// ring. Nil when no countdown is running.
    private(set) var commercialMuteTotalSeconds: Int?
    /// Non-nil while a sleep timer is counting down; when it elapses the TV is put to sleep
    /// (standby). Drives the sleep-timer dial's ring.
    private(set) var sleepTimerRemaining: Duration?
    /// Total seconds of the running sleep timer — drives the dial's ring fraction.
    private(set) var sleepTimerTotalSeconds: Int?
    /// Non-nil while a wake timer is counting down; when it elapses the TV is woken via
    /// Wake-on-LAN and (optionally) tuned to a channel. Drives the wake-timer dial's ring.
    private(set) var wakeTimerRemaining: Duration?
    /// Total seconds of the running wake timer — drives the dial's ring fraction.
    private(set) var wakeTimerTotalSeconds: Int?
    /// Nil until the user has asked the TV for its app list at least once.
    private(set) var installedApps: [InstalledApp]?
    private(set) var isLoadingInstalledApps: Bool = false

    private var commercialMuteTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var wakeTimerTask: Task<Void, Never>?
    private var liveTuneTask: Task<Void, Never>?
    /// Pacing between digits of the post-wake tune macro (matches the EPG tune delay).
    private let tuneInterKeyDelayMs = 120
    /// Settle time before the channel scroll-picker actually tunes, so flicking the wheel
    /// doesn't fire a tune per row.
    private let liveTuneDebounceMs = 250
    /// Extra wait after the post-wake reconnect before sending channel digits — the socket
    /// often connects several seconds before the TV input is ready to accept a channel.
    private let postWakeTuneSettleSeconds = 15
    private let commercialMuteDurationSeconds: Int = 120
    /// Gap between the two volume keys of the deterministic mute/unmute nudge, so the TV
    /// registers them as distinct presses (same pacing rationale as the tune macro).
    private let muteNudgeDelayMs = 120
    /// Optional — when injected, the power button switches to "wake mode" while the
    /// WebSocket isn't reachable, and a tap fires a Wake-on-LAN magic packet instead
    /// of `KEY_POWER`. Nil in tests or in any host that doesn't ship a wake service.
    private let wakeService: (any WakeOnLANService)?
    /// Optional — used by ``wakeAndReconnect()`` to look up the TV's MAC by IP.
    /// The MAC is captured into the remembered-TVs store on the first successful
    /// connect, so a freshly-paired TV becomes wakeable from then on.
    private let rememberedTVsStore: (any RememberedTVsStore)?
    /// How long to wait after sending a magic packet before retrying `connect()` —
    /// gives the TV time to bring its NIC up and accept the WebSocket.
    private let postWakeReconnectDelay: Duration = .seconds(5)

    init(
        device: TVDevice,
        service: any TVService,
        wakeService: (any WakeOnLANService)? = nil,
        rememberedTVsStore: (any RememberedTVsStore)? = nil
    ) {
        self.device = device
        self.service = service
        self.wakeService = wakeService
        self.rememberedTVsStore = rememberedTVsStore
    }

    var state: TVConnectionState { service.state }
    var mode: TVConnectionMode { device.mode }
    var sniffLog: [SniffLogEntry] { service.sniffLog }
    var tvPowerState: TVPowerState { service.tvPowerState }

    /// True when `KEY_POWER` over the WebSocket would be a no-op, so the power button
    /// should fire a Wake-on-LAN magic packet instead (amber ring, WoL on tap, help
    /// sheet on long-press). This is what lets the red power button wake a TV that's
    /// been off without bouncing through Discovery to find the Wake button.
    ///
    /// Wake mode covers every state except "live socket to a TV that's actually on":
    /// - `.disconnected` / `.failed` — no channel; only WoL can bring the TV back.
    /// - `.connecting` — included on purpose: when the TV is off, the connect attempt
    ///   can hang for many seconds before failing, and we don't want the user stuck
    ///   pressing a dead power button during that window.
    /// - `.connected` but `tvPowerState == .off` — the TV slipped into standby (or the
    ///   socket is stale against a TV that was turned off behind our back); wake it.
    /// `.unknown` power state while connected is treated as "on" so the button doesn't
    /// flicker amber for the second or two before the first REST poll lands.
    var isInWakeMode: Bool {
        switch service.state {
        case .disconnected, .failed, .connecting:
            return true
        case .awaitingPairing:
            return false
        case .connected:
            return tvPowerState == .off
        }
    }

    func clearSniffLog() {
        service.clearSniffLog()
    }

    /// Runs one service call, clearing ``lastError`` on success and surfacing the error's
    /// `displayMessage` on failure. Every fire-and-report action below funnels through here
    /// so they all report identically.
    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = error.displayMessage
        }
    }

    /// Kicks off the WebSocket handshake. Called from ``RemoteView``'s `.task` so the connect
    /// attempt starts the moment the user pushes into the remote — the `StatusPill` animates
    /// through `.connecting` → `.awaitingPairing` → `.connected` as the service drives state.
    func connect() async {
        await perform { try await service.connect(to: device) }
    }

    func send(_ command: TVCommand) async {
        await perform { try await service.send(command) }
    }

    /// Pushes typed text to the TV's currently-focused text field via `SendInputString` — the
    /// same transport voice dictation uses. No-ops on the TV unless a field has focus there
    /// (e.g. a search box is open), so the on-screen ``KeyboardInputView`` tells the user to
    /// open one first.
    func sendKeyboardText(_ text: String) async {
        await perform { try await service.sendText(text) }
    }

    /// Test phrase for the Sniff Log "Send text" button (`SendInputString` probe).
    static let dictationTestPhrase = "next channel"

    // MARK: - Voice (hold-to-talk Bixby) — see Bixby.md

    /// Mic capture engine, owned for the VM's lifetime. Produces 16 kHz mono PCM
    /// chunks while a voice session is active.
    private let microphone = MicrophoneCaptureService()
    /// Pumps mic chunks to the service in order; awaited (not cancelled) on stop so the
    /// last chunks flush before the end-of-stream marker.
    private var voicePumpTask: Task<Void, Never>?
    /// True while streaming to Bixby — drives the mic button's "listening" look.
    private(set) var isListening = false

    /// Press-down on the mic button: request mic access, open Bixby, and start
    /// streaming microphone audio until ``stopVoice()``.
    func startVoice() async {
        guard !isListening else { return }
        print("[RemoteTV] voice: mic button pressed — requesting permission")
        guard await MicrophoneCaptureService.requestPermission() else {
            print("[RemoteTV] voice: microphone permission DENIED")
            lastError = TVServiceError.microphoneDenied.errorDescription
            return
        }
        do {
            // Warm the mic engine BEFORE opening Bixby so audio can start the instant
            // the TV is ready — otherwise Bixby times out and closes before the first
            // chunk arrives. The gate stays shut (audio discarded) until beginStreaming().
            print("[RemoteTV] voice: permission granted — warming mic")
            let stream = try microphone.start()
            print("[RemoteTV] voice: opening Bixby session")
            try await service.beginVoiceSession()
            microphone.beginStreaming()   // recording confirmed — open the audio gate now
            isListening = true
            lastError = nil
            voicePumpTask = Task { [weak self] in
                await self?.pumpVoice(stream)
            }
        } catch {
            microphone.stop()   // tear the warmed engine back down on failure
            print("[RemoteTV] voice: startVoice failed — \(error)")
            lastError = error.displayMessage
        }
    }

    /// Release on the mic button: stop the mic, drain the stream in order, then send
    /// the end-of-stream marker.
    func stopVoice() async {
        guard isListening else { return }
        print("[RemoteTV] voice: mic button released — stopping")
        isListening = false
        microphone.stop()           // finishes the AsyncStream
        await voicePumpTask?.value  // let the pump drain remaining chunks
        voicePumpTask = nil
        await service.endVoiceSession()
        print("[RemoteTV] voice: session ended")
    }

    /// Forwards mic chunks to the TV sequentially. Runs on the main actor (it only
    /// awaits the main-actor service), so chunks are sent strictly in order.
    private func pumpVoice(_ stream: AsyncStream<Data>) async {
        for await chunk in stream {
            try? await service.sendVoiceChunk(chunk)
        }
    }

    /// One experimental "does this open Bixby?" candidate. Edit ``bixbyProbes`` to try
    /// other key codes — each renders as a labelled button in the Sniff Log panel, and
    /// the resulting frame (plus any TV reply) shows up in the log so you can tell which
    /// one the TV actually reacts to.
    struct BixbyProbe: Identifiable, Sendable {
        let id = UUID()
        /// Short text on the button.
        let label: String
        /// The raw key code sent to the TV (not necessarily a real/known code — that's
        /// the point of probing).
        let keyCode: String
        /// Press-and-hold instead of a single click. The physical remote's voice button
        /// is a hold, so this is worth trying for the voice/Bixby case.
        var hold: Bool = false
    }

    /// The probe set wired into the Sniff Log panel. `KEY_BT_VOICE` is the confirmed
    /// "open Bixby" code; add or change codes freely while hunting.
    static let bixbyProbes: [BixbyProbe] = [
        .init(label: "BT_VOICE", keyCode: "KEY_BT_VOICE"),
    ]

    /// Sends ``dictationTestPhrase`` as a one-shot text frame (no Bixby key first), so
    /// it can be fired manually right after the BT_VOICE button. The readable text and
    /// the wire frame both land in ``sniffLog``.
    func sendTestText() async {
        await perform { try await service.sendText(Self.dictationTestPhrase) }
    }

    /// Fires one ``BixbyProbe`` at the TV. Surfaces failures on ``lastError`` like the
    /// other send paths; the sent frame and any TV response appear in ``sniffLog``.
    func runProbe(_ probe: BixbyProbe) async {
        await perform { try await service.sendRawKey(probe.keyCode, hold: probe.hold) }
    }

    func launchApp(appID: String) async {
        await perform { try await service.launch(appID: appID) }
    }

    /// A YouTube "radio" link to cast as a demo target. Carries a video id, an auto-radio
    /// playlist, and a start offset — the three things YouTube's DIAL launch honours.
    static let youtubeCastURL = "https://www.youtube.com/watch?v=wL8DVHuWI7Y&list=RDqUundAa9j4M&index=3"
    //static let youtubeCastURL = "https://www.youtube.com/watch?v=qUundAa9j4M&list=RDqUundAa9j4M&start_radio=1&t=2649s"

    /// Casts the YouTube link to the TV's YouTube app over the Lounge protocol — the same
    /// path the cast icon uses, so the app opens straight to that video/playlist at the right
    /// timestamp (not just YouTube's home screen). Parses the watch URL into its video id,
    /// playlist, and start offset and hands them to the service's full DIAL+Lounge flow.
    func castYouTube() async {
        guard let parsed = Self.parseYouTube(from: Self.youtubeCastURL) else {
            lastError = "Could not parse the YouTube URL"
            return
        }
        await perform {
            try await service.castYouTubeVideo(
                videoId: parsed.videoId,
                listId: parsed.listId,
                startSeconds: parsed.startSeconds
            )
        }
    }

    /// Splits a `youtube.com/watch?...` URL into the pieces the Lounge `setPlaylist` command
    /// needs: `v` (video id, required), `list` (playlist, optional), and `t` (start time —
    /// any trailing `s` stripped to bare seconds). Returns `nil` if there's no video id.
    static func parseYouTube(from urlString: String) -> (videoId: String, listId: String?, startSeconds: Int)? {
        guard let items = URLComponents(string: urlString)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let videoId = value("v") else { return nil }
        let listId = value("list")
        var startSeconds = 0
        if let t = value("t") {
            let digits = t.hasSuffix("s") ? String(t.dropLast()) : t
            startSeconds = Int(digits) ?? 0
        }
        return (videoId, listId, startSeconds)
    }

    /// "Get me back to live TV" — a compound action that works from inside apps that would
    /// otherwise swallow `KEY_TV`. First sends `KEY_EXIT` (apps generally let this bubble
    /// up to Tizen), waits for the app to tear down, then selects the tuner with `KEY_TV`.
    /// Pressing `KEY_TV` alone from inside Netflix/HBO does nothing because the app has
    /// input focus and doesn't handle that key.
    func goLive() async {
        await send(.exit)
        try? await Task.sleep(for: .milliseconds(500))
        await send(.liveTV)
    }

    func disconnect() async {
        cancelCommercialMute()
        cancelSleepTimer()
        cancelWakeTimer()
        liveTuneTask?.cancel()
        liveTuneTask = nil
        isMuted = false
        await service.disconnect()
    }

    /// Hook for the view's scene-phase observer. Called every time the app comes back
    /// to `.active` so the service can transparently re-handshake if iOS killed the
    /// WebSocket while the app was suspended (lock screen, app-switcher). Resolves the
    /// outer error banner on a successful reconnect so the UI doesn't show a stale
    /// failure.
    func reconnectIfNeeded() async {
        await service.reconnectIfNeeded()
        if service.state == .connected {
            lastError = nil
        }
    }

    func forgetTV() async {
        await service.forget(device)
    }

    /// Routed by `PowerButton`'s tap. In normal (connected) operation this fires
    /// `KEY_POWER` over the WebSocket; when ``isInWakeMode`` is true the WebSocket
    /// is presumed dead so we send a Wake-on-LAN magic packet instead and try to
    /// reconnect after a short delay.
    func handlePowerTap() async {
        if isInWakeMode {
            await wakeAndReconnect()
        } else {
            await send(.power)
        }
    }

    /// How many times to retry the post-wake reconnect. A TV cold-booting from fully
    /// off can take 15–20 s to bring up its WebSocket server — one attempt at +5 s
    /// usually lands before it's ready, leaving the user stuck. We retry up to this
    /// many times (``postWakeReconnectDelay`` apart) so waking "just works".
    private let postWakeReconnectAttempts = 5

    /// Sends a Wake-on-LAN magic packet to the TV's stored MAC and then keeps trying to
    /// reconnect until the TV has finished booting — so the user can press the power
    /// button to wake the TV and end up back in a live session without ever leaving the
    /// remote screen.
    func wakeAndReconnect() async {
        let outcome = await sendWake()
        switch outcome {
        case .sent:
            lastError = nil
            for _ in 0..<postWakeReconnectAttempts {
                try? await Task.sleep(for: postWakeReconnectDelay)
                await connect()
                if service.state == .connected { return }
            }
        case .macUnknown:
            lastError = "Connect once while the TV is on so the app can capture its MAC."
        case .wakeServiceMissing:
            lastError = "Wake-on-LAN isn't available in this build."
        case .failed(let message):
            lastError = "Wake failed: \(message)"
        }
    }

    /// Pure dispatch path — no UI state side effects. Returns the outcome so callers
    /// can present feedback their own way (the view model itself surfaces it via
    /// `lastError`, but a unit test can assert on the outcome directly).
    ///
    /// MAC resolution prefers the one carried on the `device` (donated by Discovery /
    /// persisted in the device JSON), falling back to the remembered-TVs store — matching
    /// the Siri / Control Center path in `TVIntentsController.togglePower`. Either source
    /// alone is enough, so a wake still works when one of them is empty.
    func sendWake() async -> RemoteWakeOutcome {
        guard let wakeService else { return .wakeServiceMissing }
        var mac = device.mac
        if mac == nil || mac?.isEmpty == true {
            mac = await rememberedTVsStore?.get(ip: device.ip)?.mac
        }
        guard let mac, !mac.isEmpty else { return .macUnknown }
        do {
            try await wakeService.wake(mac: mac, ip: device.ip)
            return .sent
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Mute button on the remote — instantly mutes or unmutes the TV (deterministically, so a
    /// physical-remote press can't desync it). Muting reveals the auto-unmute scheduler in the
    /// central area; unmuting also cancels any pending auto-unmute.
    func toggleMute() async {
        if isMuted {
            await unmuteNow()
        } else {
            await forceMute()
            isMuted = true
        }
    }

    /// Unmutes the TV now and cancels any pending auto-unmute. No-op when already unmuted.
    func unmuteNow() async {
        cancelCommercialMute()
        guard isMuted else { return }
        await forceUnmute()
        isMuted = false
    }

    /// Schedules the TV to auto-unmute after `seconds` — the scheduler dial's "Auto-unmute
    /// in …" action. Mutes first if it isn't already, then starts/replaces the countdown.
    func scheduleUnmute(after seconds: Int) async {
        if !isMuted {
            await forceMute()
            isMuted = true
        }
        startUnmuteCountdown(seconds)
    }

    /// Toolbar "commercial break" control: tap to mute + auto-unmute after the default 2
    /// minutes; tap again to unmute now.
    func toggleCommercialMute() async {
        if isMuted {
            await unmuteNow()
        } else {
            await scheduleUnmute(after: commercialMuteDurationSeconds)
        }
    }

    /// Starts (or replaces) the auto-unmute countdown. Assumes the TV is already muted.
    private func startUnmuteCountdown(_ seconds: Int) {
        commercialMuteTask?.cancel()
        let total = max(1, seconds)
        commercialMuteTotalSeconds = total
        commercialMuteRemaining = .seconds(total)

        commercialMuteTask = Task { [weak self] in
            for remaining in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                if remaining > 0 {
                    self.commercialMuteRemaining = .seconds(remaining)
                }
            }
            guard let self else { return }
            self.commercialMuteRemaining = nil
            self.commercialMuteTotalSeconds = nil
            self.commercialMuteTask = nil
            await self.forceUnmute()
            self.isMuted = false
        }
    }

    // MARK: - Sleep timer

    /// Schedules the TV to sleep (standby) after `seconds`. The sleep-timer dial's
    /// "Sleep in …" action. Replaces any existing sleep timer; the close button leaves the
    /// countdown running so the TV still sleeps after the dial is dismissed.
    func scheduleSleep(after seconds: Int) {
        sleepTimerTask?.cancel()
        let total = max(1, seconds)
        sleepTimerTotalSeconds = total
        sleepTimerRemaining = .seconds(total)

        sleepTimerTask = Task { [weak self] in
            for remaining in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                if remaining > 0 {
                    self.sleepTimerRemaining = .seconds(remaining)
                }
            }
            guard let self else { return }
            self.sleepTimerRemaining = nil
            self.sleepTimerTotalSeconds = nil
            self.sleepTimerTask = nil
            // KEY_POWER toggles standby — on a TV that's awake (it has to be, to be running
            // the timer) this puts it to sleep.
            await self.send(.power)
        }
    }

    /// Cancels a pending sleep timer (the dial's Cancel button). No-op when idle.
    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemaining = nil
        sleepTimerTotalSeconds = nil
    }

    // MARK: - Wake timer

    /// Schedules the TV to wake after `seconds`: when the countdown ends it sends a
    /// Wake-on-LAN magic packet, reconnects as the TV boots, then (if `channel` is given)
    /// tunes to that channel. Replaces any existing wake timer.
    func scheduleWake(after seconds: Int, channel: Int?) {
        wakeTimerTask?.cancel()
        let total = max(1, seconds)
        wakeTimerTotalSeconds = total
        wakeTimerRemaining = .seconds(total)

        wakeTimerTask = Task { [weak self] in
            for remaining in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                if remaining > 0 {
                    self.wakeTimerRemaining = .seconds(remaining)
                }
            }
            guard let self else { return }
            self.wakeTimerRemaining = nil
            self.wakeTimerTotalSeconds = nil
            self.wakeTimerTask = nil
            // Wake-on-LAN + reconnect (retries while the TV boots).
            await self.wakeAndReconnect()
            guard let channel else { return }
            // The socket can come up before the TV input is ready to accept channel digits,
            // so wait an extra settle period (and re-ensure the connection) before tuning —
            // otherwise the digits land on a still-booting TV and the channel never changes.
            try? await Task.sleep(for: .seconds(self.postWakeTuneSettleSeconds))
            if self.service.state != .connected { await self.connect() }
            if self.service.state == .connected {
                await self.tune(to: channel)
            }
        }
    }

    /// Cancels a pending wake timer (the dial's Cancel button). No-op when idle.
    func cancelWakeTimer() {
        wakeTimerTask?.cancel()
        wakeTimerTask = nil
        wakeTimerRemaining = nil
        wakeTimerTotalSeconds = nil
    }

    /// Live tune from the channel scroll-picker: tunes to `channel` after a short debounce,
    /// cancelling any pending tune. The debounce means flicking through the wheel doesn't
    /// flood the TV — it switches once the selection settles for a moment.
    func tuneLive(to channel: Int) {
        liveTuneTask?.cancel()
        liveTuneTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(liveTuneDebounceMs))
            if Task.isCancelled { return }
            guard let self else { return }
            await self.tune(to: channel)
        }
    }

    /// Tunes to a channel number by sending its digits followed by `KEY_ENTER`, paced so
    /// Tizen doesn't drop fast-arriving digits (same rationale as the EPG tune macro).
    private func tune(to channel: Int) async {
        let digits = String(channel).compactMap(\.wholeNumberValue)
        let commands = digits.compactMap(TVCommand.digit) + [.enter]
        for (index, command) in commands.enumerated() {
            await send(command)
            if index < commands.count - 1 {
                try? await Task.sleep(for: .milliseconds(tuneInterKeyDelayMs))
            }
        }
    }

    /// Deterministically unmutes the TV. On Samsung, volume keys *always* cancel mute (they
    /// never toggle it), so a net-zero up→down nudge guarantees the TV ends unmuted no matter
    /// what state it was in — including after a physical-remote mute press. Side effects: a
    /// brief volume OSD, and ±1 step only at the volume extremes.
    private func forceUnmute() async {
        await send(.volumeUp)
        try? await Task.sleep(for: .milliseconds(muteNudgeDelayMs))
        await send(.volumeDown)
    }

    /// Deterministically mutes the TV: normalise to a known *unmuted* state via the volume
    /// nudge, then a single `KEY_MUTE` lands on muted.
    private func forceMute() async {
        await forceUnmute()
        try? await Task.sleep(for: .milliseconds(muteNudgeDelayMs))
        await send(.mute)
    }

    /// Clears any cached app list and asks the TV for a fresh one. Per the UI spec: one tap
    /// loads, subsequent taps clear-and-reload — so the user can refresh after installing or
    /// uninstalling an app on the TV without tearing down the connection.
    func refreshInstalledApps() async {
        installedApps = nil
        isLoadingInstalledApps = true
        defer { isLoadingInstalledApps = false }

        await perform {
            installedApps = try await service.requestInstalledApps()
        }
    }

    private func cancelCommercialMute() {
        commercialMuteTask?.cancel()
        commercialMuteTask = nil
        commercialMuteRemaining = nil
        commercialMuteTotalSeconds = nil
    }
}
