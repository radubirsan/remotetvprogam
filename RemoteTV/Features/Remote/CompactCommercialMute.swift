import SwiftUI

/// Compact pill version of the commercial-break mute affordance, sized to fit in the
/// dark Samsung-style header strip alongside the settings gear. When armed, the pill
/// turns red and shows a live countdown; tapping it again unmutes early. See
/// ``RemoteViewModel/toggleCommercialMute`` for the underlying state machine.
@MainActor
struct CompactCommercialMute: View {
    let remaining: Duration?
    let onToggle: () async -> Void

    var body: some View {
        Button {
            Task { await onToggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isArmed ? "speaker.slash.fill" : "speaker.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .monospacedDigit()
            }
            .foregroundStyle(isArmed ? .white : RemoteTheme.iconColor)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(background, in: .capsule)
            .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isArmed: Bool { remaining != nil }

    private var label: String {
        if let remaining {
            return remaining.formatted(.time(pattern: .minuteSecond))
        }
        return "2 MIN"
    }

    private var background: AnyShapeStyle {
        if isArmed {
            return AnyShapeStyle(Color.red)
        }
        return AnyShapeStyle(RemoteTheme.buttonFace)
    }

    private var accessibilityLabel: Text {
        if let remaining {
            return Text("Unmute now. Otherwise auto-unmutes in \(remaining.formatted(.time(pattern: .minuteSecond))).")
        }
        return Text("Mute the TV for two minutes.")
    }
}
