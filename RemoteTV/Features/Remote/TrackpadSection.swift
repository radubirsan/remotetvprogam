import RemoteTVCore
import SwiftUI

/// Virtual trackpad with a jog-wheel overlay.
///
/// **Swipe / tap** (unchanged): a quick straight drag is classified by
/// ``TrackpadGestureMapper`` as a tap (`KEY_ENTER`) or a directional swipe (the matching
/// arrow key), each with a medium impact haptic.
///
/// **Jog wheel**: holding down and moving in a circle spins the surface (the icon, the
/// "SWIPE / TAP" label and a ring of tick marks all rotate to follow the finger) and steps
/// the TV volume — clockwise = volume up, counter-clockwise = volume down — with a light
/// detent haptic per step. A ``JogWheelTracker`` decides "is this a spin?" from the path's
/// curvature, so an ordinary swipe never triggers it. Releasing snaps the wheel back to its
/// resting position and re-arms the swipe/tap classifier.
///
/// Styled as a circular dark surface matching the design's `DPad` wheel — same diameter,
/// same `RemoteTheme.dpadOuter` fill — so toggling between D-Pad and Trackpad never shifts
/// the surrounding layout.
@MainActor
struct TrackpadSection: View {
    /// Diameter of the trackpad surface. Matches the design's D-Pad outer ring so the
    /// two modes occupy identical screen real estate.
    var diameter: CGFloat = 150
    let onCommand: (TVCommand) async -> Void

    /// Monotonically increasing counter used purely as a `.sensoryFeedback` trigger —
    /// any change in value re-fires the impact haptic. `&+=` so an unbounded user
    /// session can't ever crash on overflow.
    @State private var swipeFeedbackTrigger: Int = 0
    /// Separate trigger for the lighter per-detent haptic while jogging.
    @State private var jogFeedbackTrigger: Int = 0

    /// One tracker per drag; reset on release.
    @State private var jog = JogWheelTracker()
    /// The wheel's current visual rotation (radians). Follows the finger live while jogging,
    /// then springs back to 0 on release.
    @State private var wheelAngle: Double = 0
    /// Mirrors ``JogWheelTracker/isEngaged`` for styling (so reading it doesn't depend on the
    /// tracker's lifetime).
    @State private var isJogging: Bool = false

    var body: some View {
        Circle()
            .fill(RemoteTheme.dpadOuter)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(jogRingColor, lineWidth: isJogging ? 1.5 : 0.5))
            .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
            .overlay { tickRing }
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(RemoteTheme.iconColor)
                    Text("SWIPE / TAP")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(RemoteTheme.labelDim)
                }
                .rotationEffect(.radians(wheelAngle))
            }
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleChange(value.location) }
                    .onEnded { value in handleEnd(value.translation) }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: swipeFeedbackTrigger)
            .sensoryFeedback(.impact(weight: .light), trigger: jogFeedbackTrigger)
            .accessibilityElement()
            .accessibilityLabel("Trackpad")
            .accessibilityHint("Swipe to navigate, tap to select, or circle to change volume")
    }

    // MARK: - Tick ring

    /// 12 faint rim ticks that rotate with the wheel — gives the spin something legible to
    /// move against and brightens while jogging to read as a live volume dial.
    private var tickRing: some View {
        let inset: CGFloat = 12
        return ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(RemoteTheme.labelDim.opacity(isJogging ? 0.55 : 0.22))
                    .frame(width: 2, height: 8)
                    .offset(y: -(diameter / 2 - inset))
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }
        }
        .rotationEffect(.radians(wheelAngle))
        .allowsHitTesting(false)
    }

    private var jogRingColor: Color {
        isJogging ? RemoteTheme.accent.opacity(0.7) : Color.white.opacity(0.06)
    }

    // MARK: - Gesture handling

    private func handleChange(_ location: CGPoint) {
        let ticks = jog.update(location: location)
        guard jog.isEngaged else { return }
        if !isJogging { isJogging = true }
        wheelAngle = jog.curvature
        guard ticks != 0 else { return }
        jogFeedbackTrigger &+= 1
        let command: TVCommand = ticks > 0 ? .volumeUp : .volumeDown
        let count = abs(ticks)
        Task {
            for _ in 0..<count { await onCommand(command) }
        }
    }

    private func handleEnd(_ translation: CGSize) {
        if jog.isEngaged {
            // A spin: ignore the net translation (don't fire a stray swipe) and snap back.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { wheelAngle = 0 }
        } else {
            handle(translation: translation)
        }
        jog = JogWheelTracker()
        isJogging = false
    }

    private func handle(translation: CGSize) {
        switch TrackpadGestureMapper.gesture(for: translation) {
        case .tap:
            Task { await onCommand(.enter) }
        case .swipe(let command):
            swipeFeedbackTrigger &+= 1
            Task { await onCommand(command) }
        }
    }
}
