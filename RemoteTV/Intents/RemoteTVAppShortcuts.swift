import AppIntents

/// Zero-setup Siri phrases — these work the moment the app is installed, no Shortcuts
/// authoring needed. Every phrase must contain `applicationName` (Apple's rule), which
/// is why they read "… with Zapy". The richer intents (tune to channel, open app,
/// volume by steps) are available in the Shortcuts app rather than here: parameterized
/// phrases over a 100+-row channel list would bloat the Siri vocabulary for little gain.
///
/// PHRASE WORDING IS LOAD-BEARING: anything that matches Siri's built-in home-control
/// vocabulary ("turn on the TV", "turn off the TV") gets routed to HomeKit *before* app
/// phrases are considered — with no home configured, Siri responds by offering HomeKit
/// setup instead of running the intent. Keep the verbs out of Siri's home domain
/// ("toggle", app-name-first forms) and don't add "turn on/off …" phrasings back.
struct RemoteTVAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleTVPowerIntent(),
            phrases: [
                "\(.applicationName) power",
                "Toggle TV power with \(.applicationName)",
                "Wake my TV with \(.applicationName)",
            ],
            shortTitle: "TV Power",
            systemImageName: "power"
        )
        AppShortcut(
            intent: MuteTVIntent(),
            phrases: [
                "\(.applicationName) mute",
                "Mute the TV with \(.applicationName)",
            ],
            shortTitle: "Mute TV",
            systemImageName: "speaker.slash"
        )
        // Parameterized on the TV-app entity: Siri builds vocabulary from
        // TVAppQuery.suggestedEntities(), so "RemoteTV open YouTube", "… open Netflix",
        // etc. all resolve from this one shortcut. Requires the
        // updateAppShortcutParameters() call in RemoteTVApp.init to (re)index.
        AppShortcut(
            intent: LaunchTVAppIntent(),
            phrases: [
                "\(.applicationName) open \(\.$app)",
                "Open \(\.$app) with \(.applicationName)",
                "Open \(\.$app) on the TV with \(.applicationName)",
            ],
            shortTitle: "Open App on TV",
            systemImageName: "play.rectangle"
        )
        // Direction is a phrase PARAMETER — separate static "channel up"/"channel down"
        // phrases would both run the intent with its default direction. "Next channel"
        // is safe as a static phrase only because the default direction is `.up`.
        AppShortcut(
            intent: ChangeTVChannelIntent(),
            phrases: [
                "\(.applicationName) channel \(\.$direction)",
                "\(.applicationName) next channel",
            ],
            shortTitle: "Change Channel",
            systemImageName: "arrow.up.arrow.down.square"
        )
        // Parameterized on the channel entity — "… tune to Digi 24" resolves against
        // the KnownChannelNumbers lineup via TVChannelQuery.suggestedEntities().
        AppShortcut(
            intent: TuneTVChannelIntent(),
            phrases: [
                "\(.applicationName) tune to \(\.$channel)",
                "Tune to \(\.$channel) with \(.applicationName)",
            ],
            shortTitle: "Tune to Channel",
            systemImageName: "tv.badge.wifi"
        )
    }
}
