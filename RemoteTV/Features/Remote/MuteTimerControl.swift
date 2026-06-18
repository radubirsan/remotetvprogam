import SwiftUI

/// Mute-timer dial shown in the remote's central area (in place of the D-pad / trackpad)
/// when the user taps **Mute**. It lets them set an exact mute duration — drag around the
/// ring or tap a preset — then start it. While running, the ring counts down and a single
/// tap unmutes early. Visual language matches the onboarding `WelcomePreviewMuteTimer`.
@MainActor
struct MuteTimerControl: View {
    /// Live countdown from the view model; non-nil while a mute timer is running.
    let remaining: Duration?
    /// Total seconds of the running timer — drives the countdown ring fraction.
    let totalSeconds: Int?
    /// Start a timer for the given number of seconds.
    let onStart: (Int) -> Void
    /// Stop a running timer and unmute now.
    let onStop: () -> Void
    /// Dismiss the dial back to the D-pad / trackpad (leaves any running timer alone).
    let onClose: () -> Void

    @State private var minutes: Int = 10
    @State private var startTrigger = 0

    private let maxMinutes = 60
    private let presets = [5, 10, 30]
    private let diameter: CGFloat = 150

    private var isRunning: Bool { remaining != nil }

    var body: some View {
        VStack(spacing: 12) {
            header
            dial
            footer
        }
        .frame(width: 275)
        .animation(.snappy, value: isRunning)
        .sensoryFeedback(.selection, trigger: minutes)
        .sensoryFeedback(.impact(weight: .medium), trigger: startTrigger)
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("MUTE TIMER")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color(white: 0.42))
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close mute timer")
            }
        }
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(RemoteTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(isRunning ? .linear(duration: 0.25) : .snappy, value: fraction)

            VStack(spacing: 2) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(RemoteTheme.accent)
                Text(centerTime)
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(isRunning ? "until unmute" : "drag to set")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color(white: 0.42))
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(.circle)
        .gesture(isRunning ? nil : dialDrag)
        .accessibilityElement()
        .accessibilityLabel("Mute duration")
        .accessibilityValue(isRunning ? "\(centerTime) until unmute" : "\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            guard !isRunning else { return }
            switch direction {
            case .increment: minutes = min(minutes + 1, maxMinutes)
            case .decrement: minutes = max(minutes - 1, 1)
            @unknown default: break
            }
        }
    }

    /// Drag anywhere on the ring to set the duration; angle from 12 o'clock, clockwise.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = diameter / 2
                let dx = value.location.x - center
                let dy = value.location.y - center
                guard hypot(dx, dy) > 22 else { return }   // ignore center jitter
                var angle = atan2(dx, -dy)                  // 0 at top, clockwise positive
                if angle < 0 { angle += 2 * .pi }
                let m = Int((angle / (2 * .pi) * Double(maxMinutes)).rounded())
                minutes = min(max(m == 0 ? maxMinutes : m, 1), maxMinutes)
            }
    }

    private var fraction: CGFloat {
        if isRunning, let remaining, let totalSeconds, totalSeconds > 0 {
            return CGFloat(seconds(remaining)) / CGFloat(totalSeconds)
        }
        return CGFloat(minutes) / CGFloat(maxMinutes)
    }

    private var centerTime: String {
        if isRunning, let remaining {
            let s = seconds(remaining)
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return "\(minutes):00"
    }

    // MARK: Footer (presets + action)

    @ViewBuilder
    private var footer: some View {
        if isRunning {
            Button(action: onStop) {
                Label("Unmute now", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unmute now")
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { m in
                        let selected = minutes == m
                        Button { minutes = m } label: {
                            Text("\(m)m")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selected ? RemoteTheme.bgInk : Color(white: 0.69))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(selected ? RemoteTheme.accent : Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    startTrigger &+= 1
                    onStart(minutes * 60)
                } label: {
                    Text("Start mute")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(RemoteTheme.bgInk)
                        .padding(.horizontal, 28)
                        .frame(height: 44)
                        .background(Capsule().fill(RemoteTheme.accent))
                        .shadow(color: RemoteTheme.accent.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start muting for \(minutes) minutes")
            }
        }
    }

    private func seconds(_ d: Duration) -> Int { Int(d.components.seconds) }
}
