import SwiftUI

/// The contents of the Samsung-style remote shell — every control that lives *inside*
/// the rounded body, laid out at the design's exact pixel coordinates (340×760,
/// matching the HIG-compliant sizing in `RemoteSamsungStyleView`). Wired to the live
/// ``RemoteViewModel``.
///
/// All tappable elements meet Apple's 44×44 minimum (the few that don't are flagged
/// inline). Positions, sizes, corner radii and shadow values all mirror the design
/// file — keeping the two in lock-step is intentional.
@MainActor
struct RemoteSamsungBody: View {
    static let width: CGFloat = 340
    static let height: CGFloat = 760

    let state: TVConnectionState
    let hasError: Bool
    let inputMode: RemoteInputMode
    let installedApps: [InstalledApp]?
    let onCommand: (TVCommand) async -> Void
    let onLiveTV: () async -> Void
    let onLaunchApp: (String) async -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Body shell — corner radius and shadow match `RemoteSamsungStyleView`.
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(RemoteTheme.body)
                .frame(width: Self.width, height: Self.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 56, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 22, y: 14)

            // ROW 1: Power (left), MIC label + status LED (centre), Mic (right).
            CircleButton(size: 56, iconColor: RemoteTheme.powerRed,
                         accessibilityLabel: "Power") {
                fire(.powerOff)
            } content: {
                Image(systemName: "power")
                    .font(.system(size: 22, weight: .heavy))
            }
            .position(x: 40 + 28, y: 36 + 28)

            VStack(spacing: 3) {
                RemoteStatusLED(state: state, hasError: hasError)
                Text("MIC")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(RemoteTheme.labelDim)
            }
            .position(x: Self.width / 2, y: 50)

            // Mic — visual placeholder per design (no voice input wired up).
            CircleButton(size: 56, accessibilityLabel: "Voice (not implemented)") {
            } content: {
                Image(systemName: "mic")
                    .font(.system(size: 20, weight: .regular))
            }
            .position(x: Self.width - 40 - 28, y: 36 + 28)

            // ROW 2: Settings/123 (under power) — visual placeholder per design.
            CircleButton(size: 56, accessibilityLabel: "Number pad (not implemented)") {
            } content: {
                VStack(spacing: 0) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .regular))
                    Text("123")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                }
            }
            .position(x: 40 + 28, y: 110 + 28)

            // CENTRAL CONTROL — D-Pad wheel or virtual trackpad, swappable from the gear menu.
            centralControl
                .position(x: Self.width / 2, y: 200 + 110)

            // ROW 4: Back / Home / Play-Pause.
            CircleButton(size: 56, accessibilityLabel: "Back") {
                fire(.back)
            } content: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 19, weight: .semibold))
            }
            .position(x: 40 + 28, y: 470 + 28)

            CircleButton(size: 64, accessibilityLabel: "Home") {
                fire(.home)
            } content: {
                Image(systemName: "house.fill")
                    .font(.system(size: 22, weight: .regular))
            }
            .position(x: Self.width / 2, y: 466 + 32)

            CircleButton(size: 56, accessibilityLabel: "Play or pause") {
                fire(.playPause)
            } content: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 18, weight: .regular))
            }
            .position(x: Self.width - 40 - 28, y: 470 + 28)

            // ROW 5: Volume rocker (left).
            Rocker(width: 120, height: 52,
                   topLabel: "Volume down", bottomLabel: "Volume up") {
                Image(systemName: "minus").font(.system(size: 18, weight: .semibold))
            } bottom: {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
            } topAction: {
                fire(.volumeDown)
            } bottomAction: {
                fire(.volumeUp)
            }
            .position(x: 40 + 60, y: 562 + 26)

            // ROW 5: Channel rocker (right).
            Rocker(width: 120, height: 52,
                   topLabel: "Channel up", bottomLabel: "Channel down") {
                Image(systemName: "chevron.up").font(.system(size: 16, weight: .semibold))
            } bottom: {
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold))
            } topAction: {
                fire(.channelUp)
            } bottomAction: {
                fire(.channelDown)
            }
            .position(x: Self.width - 40 - 60, y: 562 + 26)

            // CC/AD + mute hint row beneath the volume rocker. The hit areas are
            // expanded via `.frame(...)` + `.contentShape(...)` so each half meets
            // a reasonable tap minimum even though the visible glyphs stay small to
            // honour the design's quiet hint-style.
            HStack(spacing: 8) {
                Button {
                    fire(.captions)
                } label: {
                    Text("CC/AD")
                        .frame(minWidth: 56, minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Closed captions")

                Button {
                    fire(.mute)
                } label: {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 12, weight: .regular))
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mute")
            }
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color(white: 0.48))
            .position(x: 40 + 60, y: 624)

            // ROW 6: App slots — only three slots in the new design (APP 1, LIVE, APP 2).
            // APP 1 and APP 2 bind dynamically to the first two installed apps the TV
            // surfaces (placeholders shown until the user opens the Installed Apps panel
            // and taps "Load Apps"). LIVE TV is the static `goLive()` action.
            appSlot(at: 0, size: 56)
                .position(x: 40 + 28, y: 656 + 28)

            AppSlot(size: 64, label: "LIVE", sublabel: "TV", accessibilityName: "Live TV") {
                Task { await onLiveTV() }
            }
            .position(x: Self.width / 2, y: 652 + 32)

            appSlot(at: 1, size: 56)
                .position(x: Self.width - 40 - 28, y: 656 + 28)

            // Brand label.
            Text("ANOTHER REMOTE")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(RemoteTheme.labelDim)
                .frame(width: Self.width)
                .position(x: Self.width / 2, y: Self.height - 28)
        }
        .frame(width: Self.width, height: Self.height)
    }

    @ViewBuilder
    private var centralControl: some View {
        switch inputMode {
        case .dpad:
            DPad(
                outerSize: 220,
                innerSize: 96,
                onUp: { fire(.up) },
                onDown: { fire(.down) },
                onLeft: { fire(.left) },
                onRight: { fire(.right) },
                onOK: { fire(.enter) }
            )
        case .trackpad:
            TrackpadSection(diameter: 220, onCommand: onCommand)
        }
    }

    /// Builds an app slot bound to the n-th installed app, falling back to a numbered
    /// placeholder when fewer than `index + 1` apps have been detected (or the user
    /// hasn't opened the Installed Apps panel and tapped "Load Apps" yet).
    @ViewBuilder
    private func appSlot(at index: Int, size: CGFloat) -> some View {
        let app = appAtIndex(index)
        AppSlot(
            size: size,
            label: slotLabel(for: app),
            sublabel: app == nil ? "\(index + 1)" : nil,
            accessibilityName: a11yName(for: app, index: index)
        ) {
            if let app {
                Task { await onLaunchApp(app.appID) }
            }
        }
    }

    private func appAtIndex(_ index: Int) -> InstalledApp? {
        guard let apps = installedApps, apps.indices.contains(index) else { return nil }
        return apps[index]
    }

    private func slotLabel(for app: InstalledApp?) -> String {
        guard let app else { return "APP" }
        let upper = app.name.uppercased()
        return String(upper.prefix(6))
    }

    private func a11yName(for app: InstalledApp?, index: Int) -> String {
        guard let app else { return "App slot \(index + 1) (empty)" }
        return "Launch \(app.name)"
    }

    private func fire(_ command: TVCommand) {
        Task { await onCommand(command) }
    }
}
