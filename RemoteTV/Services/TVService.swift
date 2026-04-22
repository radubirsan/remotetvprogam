import Foundation

/// Transport-agnostic protocol for a device that can relay remote key presses to a TV.
///
/// Marked `@MainActor` so that view models can read `state` synchronously off the main thread
/// without bridging. Implementations that do I/O off-main should hop back before mutating state.
@MainActor
protocol TVService: AnyObject {
    var state: TVConnectionState { get }
    func connect(to device: TVDevice) async throws
    func send(_ command: TVCommand) async throws
    /// Launches a Tizen app by ID. Works for both hard-coded shortcuts (``TVApp``) and
    /// dynamically discovered apps from ``requestInstalledApps()``.
    func launch(appID: String) async throws
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
}
