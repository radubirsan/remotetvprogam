import AppIntents

/// Foregrounds the app for the Control Center "Open RemoteTV" control.
///
/// This file is a member of BOTH the app target AND the `RemoteTVExtension` target — that
/// dual membership is load-bearing. The control (in the extension) references this intent for
/// its button; the system then opens the app and runs `perform()` in the APP's process, which
/// is where `openAppWhenRun` actually foregrounds the app. If the type existed only in the
/// extension, tapping the control wouldn't open the app (the failure we hit). It can't live in
/// `RemoteTVCore` either — SwiftPM doesn't run the AppIntents metadata-extraction build phase,
/// so a package-defined intent never registers. Hence: plain `.swift` file, both targets.
struct OpenRemoteTVAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open RemoteTV"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
