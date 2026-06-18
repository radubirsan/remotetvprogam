import SwiftUI

/// A circular countdown scheduler shown in the remote's central area (in place of the
/// D-pad / trackpad). Used for the **mute timer** (auto-unmute), the **sleep timer**
/// (auto-standby), and the **wake timer** (Wake-on-LAN + tune) — the `Config` swaps the
/// icon, labels, presets, and range. The ring is the same size as the trackpad; the
/// readout, presets/channel picker, and schedule button all sit *inside* it. Drag the ring
/// to set an exact delay, or tap a preset, then schedule. Only the close button lives
/// outside the ring — it returns to the D-pad (any countdown keeps running). Visual language
/// matches the onboarding `WelcomePreviewMuteTimer`.
@MainActor
struct CircularTimerControl: View {
    struct Config {
        let icon: String
        /// Verb for the schedule button, e.g. "Auto-unmute" → "Auto-unmute in 10:00".
        let verb: String
        /// Sub-label under the time while counting down, e.g. "until unmute".
        let runningLabel: String
        /// Hint shown while counting down when there's no Cancel button.
        let runningHint: String
        let presets: [Int]
        let maxMinutes: Int
        let defaultMinutes: Int
    }

    /// A pickable channel for the wake timer's scrolling picker.
    struct Channel: Identifiable, Hashable {
        let number: Int
        let name: String
        var id: Int { number }
    }

    let config: Config
    /// Live countdown from the view model; non-nil while scheduled.
    let remaining: Duration?
    /// Total seconds of the running countdown — drives the ring fraction.
    let totalSeconds: Int?
    /// Schedule the action this many seconds from now.
    let onSchedule: (Int) -> Void
    /// Dismiss back to the D-pad / trackpad (leaves any countdown running).
    let onClose: () -> Void
    /// When set, a Cancel button is shown while counting down (used by the sleep + wake
    /// timers, which have no external cancel affordance). Mute leaves this nil — its Mute
    /// button cancels instead.
    var onCancelCountdown: (() -> Void)?
    /// When `selectedChannel` is non-nil, a scrolling channel picker replaces the presets
    /// (the wake timer) so the user can pick the channel to tune to once the TV is up.
    var channels: [Channel] = []
    var selectedChannel: Binding<Int?>?

    @State private var minutes: Int
    @State private var scheduleTrigger = 0

    /// Matches `RemoteSamsungBody`'s trackpad / D-pad outer size.
    private let diameter: CGFloat = 275

    init(
        config: Config,
        remaining: Duration?,
        totalSeconds: Int?,
        onSchedule: @escaping (Int) -> Void,
        onClose: @escaping () -> Void,
        onCancelCountdown: (() -> Void)? = nil,
        channels: [Channel] = [],
        selectedChannel: Binding<Int?>? = nil
    ) {
        self.config = config
        self.remaining = remaining
        self.totalSeconds = totalSeconds
        self.onSchedule = onSchedule
        self.onClose = onClose
        self.onCancelCountdown = onCancelCountdown
        self.channels = channels
        self.selectedChannel = selectedChannel
        _minutes = State(initialValue: config.defaultMinutes)
    }

    private var isCountingDown: Bool { remaining != nil }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(RemoteTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(isCountingDown ? .linear(duration: 0.25) : .snappy, value: fraction)

            innerContent
                .padding(.horizontal, 40)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(.circle)
        // Drag the ring to set the delay. `simultaneousGesture` + the radius guard let taps
        // and the channel picker's scroll work, while a drag on the outer band sets the time.
        .simultaneousGesture(dialDrag)
        .overlay(alignment: .topTrailing) { closeButton }
        .sensoryFeedback(.selection, trigger: minutes)
        .sensoryFeedback(.impact(weight: .medium), trigger: scheduleTrigger)
    }

    // MARK: Inner content

    @ViewBuilder
    private var innerContent: some View {
        if isCountingDown {
            countdownContent
        } else if let selectedChannel {
            wakeContent(selectedChannel)
        } else {
            timerContent
        }
    }

    /// Counting-down layout (shared): ring readout + cancel / hint.
    private var countdownContent: some View {
        VStack(spacing: 8) {
            icon
            time
            Text(config.runningLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(white: 0.42))
            countdownFooter.padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
    }

    /// Mute / sleep idle layout: readout + presets + schedule.
    private var timerContent: some View {
        VStack(spacing: 8) {
            icon
            time
            Text("drag to set")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(white: 0.42))
            presetRow.padding(.top, 4)
            scheduleButton
        }
        .accessibilityElement(children: .contain)
    }

    /// Wake idle layout: compact time at top, channel picker in the middle, schedule below.
    private func wakeContent(_ selection: Binding<Int?>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: config.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(RemoteTheme.accent)
                Text(centerTime)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            channelPicker(selection)
            scheduleButton
        }
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        Image(systemName: config.icon)
            .font(.system(size: 26))
            .foregroundStyle(RemoteTheme.accent)
    }

    private var time: some View {
        Text(centerTime)
            .font(.system(size: 30, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var countdownFooter: some View {
        if let onCancelCountdown {
            Button(action: onCancelCountdown) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel timer")
        } else {
            Text(config.runningHint)
                .font(.system(size: 10, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(white: 0.42))
        }
    }

    private func channelPicker(_ selection: Binding<Int?>) -> some View {
        Picker("Channel", selection: selection) {
            Text("Just wake").tag(Int?.none)
            ForEach(channels) { ch in
                Text("\(ch.number)  \(ch.name)")
                    .lineLimit(1)
                    .tag(Int?.some(ch.number))
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 154, height: 96)
        .clipped()
        .accessibilityLabel("Channel to tune to")
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(config.presets, id: \.self) { m in
                let selected = minutes == m
                Button { minutes = m } label: {
                    Text("\(m)m")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? RemoteTheme.bgInk : Color(white: 0.69))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? RemoteTheme.accent : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var scheduleButton: some View {
        Button {
            scheduleTrigger &+= 1
            onSchedule(minutes * 60)
        } label: {
            Text("\(config.verb) in \(minutes):00")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(RemoteTheme.bgInk)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(RemoteTheme.accent))
                .shadow(color: RemoteTheme.accent.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(config.verb) in \(minutes) minutes")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.06)))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to D-pad")
    }

    // MARK: Dial gesture

    /// Drag near the ring to set the delay; angle from 12 o'clock, clockwise. The
    /// `minimumDistance` and the radius guard keep taps / the channel scroll from moving it.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isCountingDown else { return }
                let center = diameter / 2
                let dx = value.location.x - center
                let dy = value.location.y - center
                guard hypot(dx, dy) > 92 else { return }    // only the outer ring band
                var angle = atan2(dx, -dy)                  // 0 at top, clockwise positive
                if angle < 0 { angle += 2 * .pi }
                let m = Int((angle / (2 * .pi) * Double(config.maxMinutes)).rounded())
                minutes = min(max(m == 0 ? config.maxMinutes : m, 1), config.maxMinutes)
            }
    }

    private var fraction: CGFloat {
        if isCountingDown, let remaining, let totalSeconds, totalSeconds > 0 {
            return CGFloat(seconds(remaining)) / CGFloat(totalSeconds)
        }
        return CGFloat(minutes) / CGFloat(config.maxMinutes)
    }

    private var centerTime: String {
        if isCountingDown, let remaining {
            let s = seconds(remaining)
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return "\(minutes):00"
    }

    private func seconds(_ d: Duration) -> Int { Int(d.components.seconds) }
}

extension CircularTimerControl.Config {
    /// Mute timer: auto-unmute the TV after the chosen delay. No Cancel button — the Mute
    /// button is the cancel affordance.
    static let mute = Self(
        icon: "speaker.slash.fill",
        verb: "Auto-unmute",
        runningLabel: "until unmute",
        runningHint: "Auto-unmutes when\nthe timer ends",
        presets: [5, 10, 30],
        maxMinutes: 60,
        defaultMinutes: 10
    )

    /// Sleep timer: put the TV into standby after the chosen delay.
    static let sleep = Self(
        icon: "moon.zzz.fill",
        verb: "Sleep",
        runningLabel: "until sleep",
        runningHint: "Sleeps when\nthe timer ends",
        presets: [15, 30, 60],
        maxMinutes: 120,
        defaultMinutes: 30
    )

    /// Wake timer: Wake-on-LAN the TV after the chosen delay, then tune to the channel
    /// picked in the dial's wheel. Presets are unused (the channel picker replaces them).
    static let wake = Self(
        icon: "alarm.fill",
        verb: "Wake",
        runningLabel: "until wake",
        runningHint: "Wakes the TV when\nthe timer ends",
        presets: [],
        maxMinutes: 240,
        defaultMinutes: 60
    )
}
