import RemoteTVCore
import SwiftUI

/// Which scheduler dial occupies the remote's central area instead of the D-pad / trackpad.
enum RemoteCentralOverlay {
    case none
    case mute
    case sleep
    case wake
}

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
    let powerState: TVPowerState
    let hasError: Bool
    let inputMode: RemoteInputMode
    let installedApps: [InstalledApp]?
    let onCommand: (TVCommand) async -> Void
    let onLiveTV: () async -> Void
    let onLaunchApp: (String) async -> Void
    /// Hold-to-talk mic. `onMicDown` fires when the finger lands (open Bixby + start
    /// streaming), `onMicUp` when it lifts (stop + send end-of-stream marker). Sync
    /// wrappers like `onPowerTap`; the parent bridges to the async VM.
    let onMicDown: () -> Void
    let onMicUp: () -> Void
    /// Power-button visual mode (green / amber ring). Parent picks this based on
    /// `RemoteViewModel.isInWakeMode`.
    let powerMode: PowerButton.Mode
    /// Sync wrapper supplied by the parent — it decides whether tap should fire
    /// `KEY_POWER` (standby) or a Wake-on-LAN packet (wake mode).
    let onPowerTap: () -> Void
    /// Long-press companion. In standby mode this fires `KEY_SLEEP`; in wake mode
    /// the parent presents `PowerOnHelpSheet` so the user can troubleshoot why the
    /// magic packet might not be arriving.
    let onPowerLongPress: () -> Void

    /// Which timer dial (if any) replaces the D-pad / trackpad in the central area. Owned by
    /// `RemoteView` so the gear menu can open the sleep timer; the Mute button and the dials'
    /// close buttons write it too.
    @Binding var centralOverlay: RemoteCentralOverlay

    /// Mute state + actions. The Mute button toggles `isMuted` (instant mute/unmute) and
    /// reveals the auto-unmute scheduler. `muteRemaining` is non-nil while a scheduled
    /// auto-unmute counts down; `muteTotalSeconds` draws the ring.
    let isMuted: Bool
    let muteRemaining: Duration?
    let muteTotalSeconds: Int?
    let onToggleMute: () -> Void
    let onScheduleUnmute: (Int) -> Void

    /// Sleep-timer state + actions (the moon button under Power). `sleepRemaining` is
    /// non-nil while counting down to standby.
    let sleepRemaining: Duration?
    let sleepTotalSeconds: Int?
    let onScheduleSleep: (Int) -> Void
    let onCancelSleep: () -> Void

    /// Wake-timer state + actions (the alarm button under Power). After the countdown the
    /// parent sends Wake-on-LAN and tunes to the entered channel. `wakeRemaining` is non-nil
    /// while counting down.
    let wakeRemaining: Duration?
    let wakeTotalSeconds: Int?
    let onScheduleWake: (_ seconds: Int, _ channel: Int?) -> Void
    let onCancelWake: () -> Void

    /// Drives the modal number-pad sheet that the 123 button summons. Local to the
    /// body since no other surface needs to read it.
    @State private var showNumberPad: Bool = false

    /// Channel number the wake timer should tune to once the TV is up (nil = just wake).
    /// Owned here so the dial's picker and the schedule action share it.
    @State private var wakeChannelNumber: Int?

    /// The tunable lineup for the wake picker, from `KnownChannelNumbers` (number + name),
    /// ordered by channel number and de-duplicated.
    private var wakeChannels: [CircularTimerControl.Channel] {
        var seen = Set<Int>()
        var result: [CircularTimerControl.Channel] = []
        for id in KnownChannelNumbers.orderedIDs {
            guard let number = KnownChannelNumbers.number(for: id), seen.insert(number).inserted else { continue }
            result.append(.init(number: number, name: KnownChannelNumbers.displayName(for: id)))
        }
        return result
    }

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
            // The dispatch logic lives in the parent so the same button can flip
            // into "wake mode" (Wake-on-LAN on tap, help sheet on long-press) when
            // the WebSocket is unreachable. Visual cue is the ring colour, driven
            // by `powerMode`.
            PowerButton(
                size: 70,
                mode: powerMode,
                onTap: onPowerTap,
                onLongPress: onPowerLongPress
            )
            .position(x: 75, y: 71)

            VStack(spacing: 3) {
                RemoteStatusLED(state: state, powerState: powerState, hasError: hasError)
                Text("MIC")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(RemoteTheme.labelDim)
            }
            .position(x: Self.width / 2, y: 50)

            // Mic — hold to talk to Bixby (streams audio while held).
            HoldToTalkMic(size: 70, onDown: onMicDown, onUp: onMicUp)
                .position(x: 265, y: 71)

            // Sleep / wake timer buttons, tucked under the Power button — they open the
            // matching dial in the central area. Tint accent while their timer is running.
            CircleButton(
                size: 36,
                iconColor: sleepRemaining != nil ? RemoteTheme.accent : RemoteTheme.iconColor,
                accessibilityLabel: "Sleep timer"
            ) {
                withAnimation(.snappy) { centralOverlay = centralOverlay == .sleep ? .none : .sleep }
            } content: {
                Image(systemName: "moon.fill").font(.system(size: 14))
            }
            .position(x: 55, y: 127)

            CircleButton(
                size: 36,
                iconColor: wakeRemaining != nil ? RemoteTheme.accent : RemoteTheme.iconColor,
                accessibilityLabel: "Wake timer"
            ) {
                withAnimation(.snappy) { centralOverlay = centralOverlay == .wake ? .none : .wake }
            } content: {
                Image(systemName: "alarm.fill").font(.system(size: 14))
            }
            .position(x: 95, y: 127)

            // ROW 2: Settings/123. Opens the modal `NumberPadView` so the user can tap a
            // channel number — each digit dispatches `KEY_<n>` to the TV the same way a
            // physical remote does.
            CircleButton(size: 70, accessibilityLabel: "Number pad") {
                showNumberPad = true
            } content: {
                VStack(spacing: 0) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                    Text("123")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                }
            }
            .position(x: 75, y: 186)

            // CENTRAL CONTROL — D-Pad wheel / virtual trackpad, or a mute / sleep timer dial.
            centralControl
                .position(x: Self.width / 2, y: 365)
                .animation(.snappy, value: isMuted)
                .animation(.snappy, value: centralOverlay)

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
                .buttonStyle(.hapticPress)
                .accessibilityLabel("Closed captions")

                Button {
                    let willMute = !isMuted
                    onToggleMute()
                    withAnimation(.snappy) { centralOverlay = willMute ? .mute : .none }
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.slash")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isMuted ? RemoteTheme.accent : Color(white: 0.48))
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.hapticPress)
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
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
        .sheet(isPresented: $showNumberPad) {
            // `.large` only — at `.medium` the bottom Enter row gets clipped because
            // the keypad needs ~470pt of vertical room and medium gives ~426pt.
            NumberPadView(onCommand: onCommand)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Drop the mute dial when the TV unmutes (button or auto-unmute) so it doesn't linger.
        .onChange(of: isMuted) { _, muted in
            if !muted && centralOverlay == .mute { centralOverlay = .none }
        }
    }

    @ViewBuilder
    private var centralControl: some View {
        if centralOverlay == .mute && isMuted {
            CircularTimerControl(
                config: .mute,
                remaining: muteRemaining,
                totalSeconds: muteTotalSeconds,
                onSchedule: onScheduleUnmute,
                onClose: { withAnimation(.snappy) { centralOverlay = .none } }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if centralOverlay == .sleep {
            CircularTimerControl(
                config: .sleep,
                remaining: sleepRemaining,
                totalSeconds: sleepTotalSeconds,
                onSchedule: onScheduleSleep,
                onClose: { withAnimation(.snappy) { centralOverlay = .none } },
                onCancelCountdown: { onCancelSleep() }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if centralOverlay == .wake {
            CircularTimerControl(
                config: .wake,
                remaining: wakeRemaining,
                totalSeconds: wakeTotalSeconds,
                onSchedule: { seconds in onScheduleWake(seconds, wakeChannelNumber) },
                onClose: { withAnimation(.snappy) { centralOverlay = .none } },
                onCancelCountdown: { onCancelWake() },
                channels: wakeChannels,
                selectedChannel: $wakeChannelNumber
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
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

/// Press-and-hold mic button. Fires `onDown` the instant the finger lands and `onUp`
/// when it lifts, so the parent can stream voice for exactly as long as the user holds
/// — mirroring the physical remote's "hold the mic button and talk" gesture. Turns red
/// and shrinks slightly while held. Uses a zero-distance `DragGesture` (like
/// ``PowerButton``) because a plain `Button` only reports a completed tap, not the
/// down/up edges we need.
private struct HoldToTalkMic: View {
    let size: CGFloat
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var pressing = false
    @State private var hapticTrigger = 0

    var body: some View {
        ZStack {
            Circle().fill(RemoteTheme.buttonFace)
                .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            Image(systemName: pressing ? "mic.fill" : "mic")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(pressing ? Color.red : RemoteTheme.iconColor)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressing ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: pressing)
        .contentShape(.circle)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    pressing = true
                    hapticTrigger &+= 1
                    onDown()
                }
                .onEnded { _ in
                    guard pressing else { return }
                    pressing = false
                    onUp()
                }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Hold to talk to Bixby")
    }
}
