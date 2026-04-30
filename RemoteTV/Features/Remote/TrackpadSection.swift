import SwiftUI

/// Virtual trackpad. A drag is classified by ``TrackpadGestureMapper`` as either a tap
/// (fires `KEY_ENTER`) or a directional swipe (fires the matching arrow key). Each
/// registered swipe also triggers a medium impact haptic so the user gets a physical
/// confirmation without having to look down from the TV.
///
/// Uses `DragGesture(minimumDistance: 0)` rather than separate tap+drag gestures so the
/// classification happens in a single recognizer — avoiding the conflict-resolution
/// flakiness you get from layering `onTapGesture` over a drag.
@MainActor
struct TrackpadSection: View {
    let onCommand: (TVCommand) async -> Void

    /// Monotonically increasing counter used purely as a `.sensoryFeedback` trigger —
    /// any change in value re-fires the impact haptic. `&+=` so an unbounded user
    /// session can't ever crash on overflow.
    @State private var swipeFeedbackTrigger: Int = 0

    var body: some View {
        VStack {
            Image(systemName: "hand.draw")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Swipe or tap")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(Color.accentColor.opacity(0.18), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 24))
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
