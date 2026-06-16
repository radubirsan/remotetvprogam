//
//  RemoteTVExtensionControl.swift
//  RemoteTVExtension
//
//  Control Center / Lock Screen controls, backed by the shared RemoteTVCore engine.
//  These run in the extension's process; TVIntentsController.resolve() builds a
//  standalone engine from shared storage (App Group + shared Keychain).
//

import AppIntents
import RemoteTVCore
import SwiftUI
import WidgetKit

struct TVPowerControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.power"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVPowerControlIntent()) {
                Label("TV Power", systemImage: "power")
            }
        }
        .displayName("TV Power")
        .description("Toggle your Samsung TV's power, or wake it if it's off.")
    }
}

struct TVMuteControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.mute"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVMuteControlIntent()) {
                Label("Mute TV", systemImage: "speaker.slash.fill")
            }
        }
        .displayName("Mute TV")
        .description("Mute or unmute your Samsung TV.")
    }
}

struct TVPowerControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle TV Power"
    static let description = IntentDescription("Toggles the TV's power, waking it with Wake-on-LAN if it's off.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await TVIntentsController.resolve().togglePower() {
        case .sentPowerKey:
            return .result(dialog: "Toggled the TV's power.")
        case .sentWakePacket:
            return .result(dialog: "The TV was off, so I sent a wake signal. Give it a few seconds.")
        }
    }
}

struct TVMuteControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute or Unmute TV"
    static let description = IntentDescription("Toggles the TV's mute over the remote connection.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().send(.mute)
        return .result(dialog: "Toggled the TV's mute.")
    }
}

// MARK: - Volume

struct TVVolumeUpControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.volumeUp"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVVolumeUpControlIntent()) {
                Label("Volume Up", systemImage: "speaker.wave.2.fill")
            }
        }
        .displayName("TV Volume Up")
        .description("Turn the TV volume up one step.")
    }
}

struct TVVolumeDownControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.volumeDown"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVVolumeDownControlIntent()) {
                Label("Volume Down", systemImage: "speaker.wave.1.fill")
            }
        }
        .displayName("TV Volume Down")
        .description("Turn the TV volume down one step.")
    }
}

struct TVVolumeUpControlIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Volume Up"
    static let description = IntentDescription("Turns the TV volume up two steps.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Two steps per press (paced by send(macro:)'s inter-key delay).
        try await TVIntentsController.resolve().send(macro: Array(repeating: .volumeUp, count: 2))
        return .result(dialog: "Volume up.")
    }
}

struct TVVolumeDownControlIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Volume Down"
    static let description = IntentDescription("Turns the TV volume down three steps.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Three steps per press (paced by send(macro:)'s inter-key delay).
        try await TVIntentsController.resolve().send(macro: Array(repeating: .volumeDown, count: 3))
        return .result(dialog: "Volume down.")
    }
}

// MARK: - Channel

struct TVChannelUpControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.channelUp"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVChannelUpControlIntent()) {
                Label("Channel Up", systemImage: "chevron.up.square.fill")
            }
        }
        .displayName("TV Channel Up")
        .description("Go to the next channel.")
    }
}

struct TVChannelDownControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.channelDown"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVChannelDownControlIntent()) {
                Label("Channel Down", systemImage: "chevron.down.square.fill")
            }
        }
        .displayName("TV Channel Down")
        .description("Go to the previous channel.")
    }
}

struct TVChannelUpControlIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Channel Up"
    static let description = IntentDescription("Switches the TV to the next channel.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().send(.channelUp)
        return .result(dialog: "Next channel.")
    }
}

struct TVChannelDownControlIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Channel Down"
    static let description = IntentDescription("Switches the TV to the previous channel.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TVIntentsController.resolve().send(.channelDown)
        return .result(dialog: "Previous channel.")
    }
}

// MARK: - Open app

struct OpenRemoteTVAppControl: ControlWidget {
    static let kind = "com.remotetv.RemoteTV.openApp"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenRemoteTVAppIntent()) {
                Label("Open RemoteTV", systemImage: "appletvremote.gen4")
            }
        }
        .displayName("Open RemoteTV")
        .description("Open the RemoteTV remote.")
    }
}

/// Just foregrounds the app. `openAppWhenRun` does the launching; `perform` has nothing to do.
struct OpenRemoteTVAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open RemoteTV"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
