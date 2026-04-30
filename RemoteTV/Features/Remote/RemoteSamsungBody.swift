import SwiftUI

/// The contents of the Samsung-style remote shell — every control that lives *inside*
/// the rounded body, laid out at the design's exact pixel coordinates (220×720,
/// matching `RemoteSamsungStyleView`). Wired to the live ``RemoteViewModel``.
///
/// Kept as its own view so the surrounding layout (header strip, mode picker,
/// installed-apps drawer) in ``RemoteView`` stays readable, and so the absolute
/// `.position(...)` math doesn't bleed into the orchestration layer.
@MainActor
struct RemoteSamsungBody: View {
    static let width: CGFloat = 220
    static let height: CGFloat = 620

    let state: TVConnectionState
    let hasError: Bool
    let inputMode: RemoteInputMode
    let installedApps: [InstalledApp]?
    let onCommand: (TVCommand) async -> Void
    let onLiveTV: () async -> Void
    let onLaunchApp: (String) async -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Body shell
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(RemoteTheme.body)
                .frame(width: Self.width, height: Self.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 18, y: 12)

            // ROW 1: Power (left), MIC label + status LED (center), Mic (right)
            CircleButton(size: 36, iconColor: RemoteTheme.powerRed) {
                fire(.powerOff)
            } content: {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .heavy))
            }
            .position(x: 22 + 18, y: 26 + 18)

            VStack(spacing: 2) {
                RemoteStatusLED(state: state, hasError: hasError)
                Text("MIC")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(RemoteTheme.labelDim)
            }
            .position(x: Self.width / 2, y: 36)

            // Mic — kept as a non-functional visual per design (no voice support yet).
            CircleButton(size: 36) {} content: {
                Image(systemName: "mic")
                    .font(.system(size: 14, weight: .regular))
            }
            .position(x: Self.width - 22 - 18, y: 26 + 18)

            // ROW 2: Settings/123 (under power). Non-functional placeholder per design.
            CircleButton(size: 36) {} content: {
                VStack(spacing: 0) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 9, weight: .regular))
                    Text("123")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.4)
                }
            }
            .position(x: 22 + 18, y: 70 + 18)

            // CENTRAL CONTROL — D-Pad wheel or virtual trackpad, swappable from the picker.
            centralControl
                .position(x: Self.width / 2, y: 130 + 75)

            // ROW 4: Back / Home / Play-Pause
            CircleButton(size: 34) {
                fire(.back)
            } content: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .position(x: 28 + 17, y: 312 + 17)

            CircleButton(size: 42) {
                fire(.home)
            } content: {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .regular))
            }
            .position(x: Self.width / 2, y: 308 + 21)

            CircleButton(size: 34) {
                fire(.playPause)
            } content: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 13, weight: .regular))
            }
            .position(x: Self.width - 28 - 17, y: 312 + 17)

            // ROW 5: Volume rocker (left)
            Rocker(width: 72, height: 32) {
                Image(systemName: "minus").font(.system(size: 13, weight: .semibold))
            } bottom: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
            } topAction: {
                fire(.volumeDown)
            } bottomAction: {
                fire(.volumeUp)
            }
            .position(x: 22 + 36, y: 372 + 16)

            // ROW 5: Channel rocker (right)
            Rocker(width: 72, height: 32) {
                Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold))
            } bottom: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            } topAction: {
                fire(.channelUp)
            } bottomAction: {
                fire(.channelDown)
            }
            .position(x: Self.width - 22 - 36, y: 372 + 16)

            // CC/AD label + speaker.slash under volume rocker — wired so the text fires
            // captions and the icon fires mute (both small targets, hence the wider hit area).
            HStack(spacing: 6) {
                Button {
                    fire(.captions)
                } label: {
                    Text("CC/AD")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Closed captions")

                Button {
                    fire(.mute)
                } label: {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 10, weight: .regular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mute")
            }
            .font(.system(size: 8, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color(white: 0.48))
            .frame(width: 72)
            .position(x: 22 + 36, y: 416)

            // ROW 6: App slots — first four installed apps + LIVE TV at center.
            appSlot(at: 0, size: 42)
                .position(x: 22 + 21, y: 450 + 21)

            AppSlot(size: 50, label: "LIVE", sublabel: "TV") {
                Task { await onLiveTV() }
            }
            .position(x: Self.width / 2, y: 446 + 25)

            appSlot(at: 1, size: 42)
                .position(x: Self.width - 22 - 21, y: 450 + 21)

            appSlot(at: 2, size: 50)
                .position(x: Self.width / 2, y: 510 + 25)

            appSlot(at: 3, size: 42)
                .position(x: Self.width - 22 - 21, y: 514 + 21)

            // Brand label
            Text("ANOTHER REMOTE")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(RemoteTheme.labelDim)
                .frame(width: Self.width)
                .position(x: Self.width / 2, y: Self.height - 28 - 6)
        }
        .frame(width: Self.width, height: Self.height)
    }

    @ViewBuilder
    private var centralControl: some View {
        switch inputMode {
        case .dpad:
            DPad(
                outerSize: 150,
                innerSize: 62,
                onUp: { fire(.up) },
                onDown: { fire(.down) },
                onLeft: { fire(.left) },
                onRight: { fire(.right) },
                onOK: { fire(.enter) }
            )
        case .trackpad:
            TrackpadSection(diameter: 150, onCommand: onCommand)
        }
    }

    /// Builds an app slot bound to the n-th installed app, falling back to a numbered
    /// placeholder when fewer than `index + 1` apps have been detected (or the user
    /// hasn't loaded the list yet).
    @ViewBuilder
    private func appSlot(at index: Int, size: CGFloat) -> some View {
        let app = appAtIndex(index)
        AppSlot(
            size: size,
            label: slotLabel(for: app),
            sublabel: app == nil ? "\(index + 1)" : nil
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

    private func fire(_ command: TVCommand) {
        Task { await onCommand(command) }
    }
}
