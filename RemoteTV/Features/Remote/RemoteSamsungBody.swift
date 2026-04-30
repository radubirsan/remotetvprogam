import SwiftUI

/// The contents of the Samsung-style remote shell — every control that lives *inside*
/// the rounded body, laid out at the design's coordinates with all interactive
/// elements scaled +25% from the previous iteration for a more comfortable hit area.
///
/// Sizes (Power/Mic/123/Back/Play 70, Home/LIVE 80, app slots 70, DPad 275/120,
/// Trackpad 275, rockers 150×65) all sit comfortably above HIG 44pt. Positions and
/// body height were re-spaced so the bigger controls still leave consistent vertical
/// gaps between rows.
@MainActor
struct RemoteSamsungBody: View {
    static let width: CGFloat = 340
    /// Bumped from 760 → 880 to absorb the +25% button growth without rows colliding.
    static let height: CGFloat = 880

    let state: TVConnectionState
    let hasError: Bool
    let inputMode: RemoteInputMode
    let installedApps: [InstalledApp]?
    let onCommand: (TVCommand) async -> Void
    let onLiveTV: () async -> Void
    let onLaunchApp: (String) async -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Body shell.
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(RemoteTheme.body)
                .frame(width: Self.width, height: Self.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 56, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 22, y: 14)

            // ROW 1: Power (left), MIC label + status LED (centre), Mic (right).
            CircleButton(size: 70, iconColor: RemoteTheme.powerRed,
                         accessibilityLabel: "Power") {
                fire(.powerOff)
            } content: {
                Image(systemName: "power")
                    .font(.system(size: 28, weight: .heavy))
            }
            .position(x: 75, y: 71)

            VStack(spacing: 3) {
                RemoteStatusLED(state: state, hasError: hasError)
                Text("MIC")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(RemoteTheme.labelDim)
            }
            .position(x: Self.width / 2, y: 50)

            // Mic — visual placeholder per design (no voice input wired up).
            CircleButton(size: 70, accessibilityLabel: "Voice (not implemented)") {
            } content: {
                Image(systemName: "mic")
                    .font(.system(size: 25, weight: .regular))
            }
            .position(x: 265, y: 71)

            // ROW 2: Settings/123 (under power) — visual placeholder per design.
            CircleButton(size: 70, accessibilityLabel: "Number pad (not implemented)") {
            } content: {
                VStack(spacing: 0) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                    Text("123")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                }
            }
            .position(x: 75, y: 159)

            // CENTRAL CONTROL — D-Pad wheel or virtual trackpad, swappable from the gear menu.
            centralControl
                .position(x: Self.width / 2, y: 365)

            // ROW 4: Back / Home / Play-Pause.
            CircleButton(size: 70, accessibilityLabel: "Back") {
                fire(.back)
            } content: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 24, weight: .semibold))
            }
            .position(x: 75, y: 559)

            CircleButton(size: 80, accessibilityLabel: "Home") {
                fire(.home)
            } content: {
                Image(systemName: "house.fill")
                    .font(.system(size: 28, weight: .regular))
            }
            .position(x: Self.width / 2, y: 559)

            CircleButton(size: 70, accessibilityLabel: "Play or pause") {
                fire(.playPause)
            } content: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 22, weight: .regular))
            }
            .position(x: 265, y: 559)

            // ROW 5: Volume rocker (left). At width 150 the rockers had to shift apart
            // (x=85 / x=255 instead of 100 / 240) to leave a 20pt gap between them.
            Rocker(width: 150, height: 65,
                   topLabel: "Volume down", bottomLabel: "Volume up") {
                Image(systemName: "minus").font(.system(size: 22, weight: .semibold))
            } bottom: {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
            } topAction: {
                fire(.volumeDown)
            } bottomAction: {
                fire(.volumeUp)
            }
            .position(x: 85, y: 663)

            // ROW 5: Channel rocker (right).
            Rocker(width: 150, height: 65,
                   topLabel: "Channel up", bottomLabel: "Channel down") {
                Image(systemName: "chevron.up").font(.system(size: 20, weight: .semibold))
            } bottom: {
                Image(systemName: "chevron.down").font(.system(size: 20, weight: .semibold))
            } topAction: {
                fire(.channelUp)
            } bottomAction: {
                fire(.channelDown)
            }
            .position(x: 255, y: 663)

            // CC/AD + mute hint row beneath the volume rocker.
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
                        .font(.system(size: 14, weight: .regular))
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mute")
            }
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color(white: 0.48))
            .position(x: 85, y: 724)

            // ROW 6: App slots — three slots (APP 1, LIVE, APP 2). APP 1 / APP 2 bind
            // dynamically to the first two installed apps the TV surfaces (placeholders
            // until the user opens the Installed Apps panel and taps "Load Apps").
            appSlot(at: 0, size: 70)
                .position(x: 75, y: 787)

            AppSlot(size: 80, label: "LIVE", sublabel: "TV", accessibilityName: "Live TV") {
                Task { await onLiveTV() }
            }
            .position(x: Self.width / 2, y: 787)

            appSlot(at: 1, size: 70)
                .position(x: 265, y: 787)

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
                outerSize: 275,
                innerSize: 120,
                onUp: { fire(.up) },
                onDown: { fire(.down) },
                onLeft: { fire(.left) },
                onRight: { fire(.right) },
                onOK: { fire(.enter) }
            )
        case .trackpad:
            TrackpadSection(diameter: 275, onCommand: onCommand)
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
