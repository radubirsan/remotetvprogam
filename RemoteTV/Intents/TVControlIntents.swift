import AppIntents

// The control intents Siri / Shortcuts / Spotlight / the Action button / Control Center
// can run. All run in-process without opening the app (`openAppWhenRun` defaults to false).
//
// They resolve their backend via `TVIntentsController.resolve()` rather than `@Dependency`:
// in the app process that returns the live controller (reusing the UI's open socket), while
// in the Control Center widget-extension process — where `AppDependencyManager` is never
// populated and `@Dependency` would trap — it builds a standalone stack from shared storage.

struct ToggleTVPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle TV Power"
    static let description = IntentDescription(
        "Toggles the TV's standby state. If the TV is unreachable, sends a Wake-on-LAN packet to wake it instead.",
        categoryName: "Controls"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await TVIntentsController.resolve().togglePower() {
        case .sentPowerKey:
            return .result(dialog: "Toggled the TV's power.")
        case .sentWakePacket:
            return .result(dialog: "The TV was unreachable, so I sent a wake signal. It may take a few seconds to start.")
        }
    }
}

struct MuteTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute or Unmute TV"
    static let description = IntentDescription(
        "Toggles the TV's mute. Samsung's mute key is a toggle, so running it again restores audio.",
        categoryName: "Controls"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().send(.mute)
        return .result(dialog: "Toggled the TV's mute.")
    }
}

enum TVVolumeDirection: String, AppEnum {
    case up
    case down

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [TVVolumeDirection: DisplayRepresentation] = [
        .up: "Up",
        .down: "Down",
    ]
}

struct AdjustTVVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust TV Volume"
    static let description = IntentDescription(
        "Turns the TV volume up or down by a number of steps.",
        categoryName: "Controls"
    )

    @Parameter(title: "Direction", default: .up)
    var direction: TVVolumeDirection

    @Parameter(title: "Steps", default: 1, inclusiveRange: (1, 10))
    var steps: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Turn the volume \(\.$direction) by \(\.$steps)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let command: TVCommand = direction == .up ? .volumeUp : .volumeDown
        try await TVIntentsController.resolve().send(macro: Array(repeating: command, count: steps))
        return .result(dialog: "Volume \(direction == .up ? "up" : "down") \(steps).")
    }
}

struct LaunchTVAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open App on TV"
    static let description = IntentDescription(
        "Opens a streaming app on the TV.",
        categoryName: "Controls"
    )

    @Parameter(title: "App")
    var app: TVAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app) on the TV")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().launchApp(appID: app.id)
        return .result(dialog: "Opening \(app.name) on the TV.")
    }
}

enum TVChannelDirection: String, AppEnum {
    case up
    case down

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [TVChannelDirection: DisplayRepresentation] = [
        .up: "Up",
        .down: "Down",
    ]
}

struct ChangeTVChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Channel"
    static let description = IntentDescription(
        "Steps the TV to the next or previous channel.",
        categoryName: "Controls"
    )

    @Parameter(title: "Direction", default: .up)
    var direction: TVChannelDirection

    static var parameterSummary: some ParameterSummary {
        Summary("Change the channel \(\.$direction)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().send(direction == .up ? .channelUp : .channelDown)
        return .result(dialog: "Channel \(direction == .up ? "up" : "down").")
    }
}

struct TuneTVChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Tune to Channel"
    static let description = IntentDescription(
        "Tunes the TV to a channel from the guide by sending its number.",
        categoryName: "Controls"
    )

    @Parameter(title: "Channel")
    var channel: TVChannelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Tune the TV to \(\.$channel)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().send(macro: EPGViewModel.tuneCommands(for: channel.number))
        return .result(dialog: "Tuning to \(channel.name), channel \(channel.number).")
    }
}
