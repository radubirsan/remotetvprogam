import RemoteTVCore
import SwiftUI

/// Virtual trackpad. A drag is classified by ``TrackpadGestureMapper`` as either a tap
/// (fires `KEY_ENTER`) or a directional swipe (fires the matching arrow key). Each
/// registered swipe also triggers a medium impact haptic so the user gets a physical
/// confirmation without having to look down from the TV.
///
/// Styled as a circular dark surface that matches the design's `DPad` wheel — same
/// diameter, same `RemoteTheme.dpadOuter` fill — so toggling between D-Pad and
/// Trackpad modes never shifts the surrounding layout.
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

    var body: some View {
        Circle()
            .fill(RemoteTheme.dpadOuter)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
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
            }
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        handle(translation: value.translation)
                    }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: swipeFeedbackTrigger)
            .accessibilityElement()
            .accessibilityLabel("Trackpad")
            .accessibilityHint("Swipe to navigate, tap to select")
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
