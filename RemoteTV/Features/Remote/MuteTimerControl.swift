import SwiftUI

/// Auto-unmute scheduler shown in the remote's central area (in place of the D-pad /
/// trackpad) while the TV is muted. The ring is the same size as the trackpad; the mute
/// readout, presets, and "Auto-unmute in …" button all sit *inside* it. Drag the ring to
/// set an exact delay, or tap a preset, then schedule. Only the close button lives outside
/// the ring — it returns to the D-pad (the TV stays muted, any countdown keeps running).
@MainActor
struct MuteTimerControl: View {
    /// Live countdown from the view model; non-nil while an auto-unmute is scheduled.
    let remaining: Duration?
    /// Total seconds of the running countdown — drives the ring fraction.
    let totalSeconds: Int?
    /// Schedule an auto-unmute this many seconds from now.
    let onSchedule: (Int) -> Void
    /// Dismiss the dial back to the D-pad / trackpad (leaves the TV muted + any countdown).
    let onClose: () -> Void

    @State private var minutes: Int = 10
    @State private var scheduleTrigger = 0

    private let maxMinutes = 60
    private let presets = [5, 10, 30]
    /// Matches `RemoteSamsungBody`'s trackpad / D-pad outer size.
    private let diameter: CGFloat = 275

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
                .padding(.horizontal, 44)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(.circle)
        // Drag the ring to set the delay. `minimumDistance` lets a stationary tap fall
        // through to the preset / schedule buttons inside, while a drag adjusts the dial.
        .gesture(isCountingDown ? nil : dialDrag)
        .overlay(alignment: .topTrailing) { closeButton }
        .sensoryFeedback(.selection, trigger: minutes)
        .sensoryFeedback(.impact(weight: .medium), trigger: scheduleTrigger)
    }

    // MARK: Inner content

    @ViewBuilder
    private var innerContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 26))
                .foregroundStyle(RemoteTheme.accent)
            Text(centerTime)
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
            Text(isCountingDown ? "until unmute" : "drag to set")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(white: 0.42))

            if isCountingDown {
                Text("Auto-unmutes when\nthe timer ends")
                    .font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.42))
                    .padding(.top, 2)
            } else {
                presetRow.padding(.top, 4)
                scheduleButton
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { m in
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
            Text("Auto-unmute in \(minutes):00")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(RemoteTheme.bgInk)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(RemoteTheme.accent))
                .shadow(color: RemoteTheme.accent.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto-unmute in \(minutes) minutes")
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
    /// `minimumDistance` and the radius guard keep taps on the inner buttons from moving it.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let center = diameter / 2
                let dx = value.location.x - center
                let dy = value.location.y - center
                guard hypot(dx, dy) > 70 else { return }    // only the outer ring band
                var angle = atan2(dx, -dy)                  // 0 at top, clockwise positive
                if angle < 0 { angle += 2 * .pi }
                let m = Int((angle / (2 * .pi) * Double(maxMinutes)).rounded())
                minutes = min(max(m == 0 ? maxMinutes : m, 1), maxMinutes)
            }
    }

    private var fraction: CGFloat {
        if isCountingDown, let remaining, let totalSeconds, totalSeconds > 0 {
            return CGFloat(seconds(remaining)) / CGFloat(totalSeconds)
        }
        return CGFloat(minutes) / CGFloat(maxMinutes)
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
