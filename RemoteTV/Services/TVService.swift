import Foundation

/// Transport-agnostic protocol for a device that can relay remote key presses to a TV.
///
/// Marked `@MainActor` so that view models can read `state` synchronously off the main thread
/// without bridging. Implementations that do I/O off-main should hop back before mutating state.
@MainActor
protocol TVService: AnyObject {
    var state: TVConnectionState { get }
    /// Last-known power state from the TV's REST info endpoint. Refreshed periodically
    /// while connected. ``TVPowerState/unknown`` means we haven't successfully polled
    /// yet (or aren't connected). The Samsung WebSocket is silent on state changes,
    /// so this REST-derived value is the only feedback signal beyond the lifecycle in
    /// ``TVConnectionState``.
    var tvPowerState: TVPowerState { get }
    func connect(to device: TVDevice) async throws
    func send(_ command: TVCommand) async throws
    /// Types a UTF-8 string into the TV's currently-focused text field via the
    /// `SendInputString` control frame. No-ops on the TV side if nothing has input
    /// focus. Used by the voice/dictation affordance to push recognized text to a
    /// search box without per-letter key navigation.
    func sendText(_ text: String) async throws
    /// Sends an arbitrary key code over the control channel — escape hatch for
    /// experimenting with codes that aren't in ``TVCommand`` (e.g. probing for the
    /// frame that opens Bixby). `hold == true` simulates a press-and-hold by sending
    /// a `Press` frame, waiting, then `Release`. Outbound frames land in ``sniffLog``
    /// so the caller can correlate them with the TV's response.
    func sendRawKey(_ keyCode: String, hold: Bool) async throws
    /// Opens the TV's voice assistant (Bixby) and waits until it's listening: sends the
    /// `KEY_BT_VOICE` Press/Release toggle, then blocks until the TV reports
    /// `ms.voiceApp.recording` (or throws ``TVServiceError/voiceNotReady`` on timeout).
    /// Call ``sendVoiceChunk(_:)`` only after this returns.
    func beginVoiceSession() async throws
    /// Streams one chunk of microphone audio (raw PCM, 16-bit LE, mono, 16 kHz) to the
    /// assistant as a binary control frame. Order matters — send chunks sequentially.
    func sendVoiceChunk(_ pcm: Data) async throws
    /// Ends the voice utterance: sends the empty end-of-stream marker and toggles the
    /// mic back off. Best-effort; never throws.
    func endVoiceSession() async
    /// Launches a Tizen app by ID. Works for both hard-coded shortcuts (``TVApp``) and
    /// dynamically discovered apps from ``requestInstalledApps()``.
    func launch(appID: String) async throws
    /// Casts a specific YouTube video to the TV's YouTube app. Launches the app via DIAL,
    /// reads the `screenId` it publishes, and drives playback over YouTube's private Lounge
    /// API — the same path Chromecast and the phone app use, so it opens the exact video
    /// (optionally a playlist + start offset) with no on-TV pairing code. The Lounge API is
    /// undocumented and can break if Google changes it.
    func castYouTubeVideo(videoId: String, listId: String?, startSeconds: Int) async throws
    /// Returns the apps the TV has installed, out of the curated catalog in
    /// ``KnownTVApps``. Implementations probe `GET /api/v2/applications/<id>` per ID since
    /// `ed.installedApp.get` is no-op'd on recent Tizen builds.
    func requestInstalledApps() async throws -> [InstalledApp]
    /// Rolling buffer of recent control-channel messages (inbound, outbound, and info
    /// events like connect/disconnect). Surfaced in the UI so the user can watch for
    /// interesting TV-originated frames — e.g. to harvest a Tizen app ID by launching
    /// the app from the physical remote while connected.
    var sniffLog: [SniffLogEntry] { get }
    func clearSniffLog()
    func disconnect() async
    /// Wipes any stored pairing token for the given TV. Next connect will re-pair.
    func forget(_ device: TVDevice) async
    /// Idempotent recovery hook called when the app returns from the background. iOS
    /// silently tears down the WebSocket while the app is suspended (lock screen,
    /// app-switcher, Control Center) and the receive loop only notices on the next
    /// read — so by the time the user is looking at the remote again, `state` may
    /// still claim `.connected` even though the next `send` would fail. Implementations
    /// should verify the live socket and re-handshake against the last device when
    /// it's gone, while no-opping when the connection is healthy or a connect attempt
    /// is already in flight.
    func reconnectIfNeeded() async
}
