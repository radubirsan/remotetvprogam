import SwiftUI

/// Power button with dual-action behaviour. A short tap fires ``onTap`` (typically
/// the regular `KEY_POWER` standby toggle); holding the button for ``longPressSeconds``
/// fires ``onLongPress`` (typically `KEY_SLEEP`, which opens Tizen's sleep-timer menu).
/// While the user is holding, a green progress ring fills around the button so they
/// can see how long until the long-press fires; releasing early just registers a tap.
///
/// Uses a `DragGesture(minimumDistance: 0)` directly so we can check whether the
/// finger is still inside the hit area at release time. Dragging out of the circular
/// hit area cancels the press (matches standard iOS button behaviour); dragging back
/// in re-arms a fresh press/long-press cycle.
@MainActor
struct PowerButton: View {
    let size: CGFloat
    let onTap: () -> Void
    let onLongPress: () -> Void
    /// How long the user has to hold for long-press to register.
    var longPressSeconds: TimeInterval = 0.9

    @State private var pressStartTime: Date?
    @State private var longPressFired = false
    @State private var longPressTimer: Task<Void, Never>?
    @State private var pressProgress: CGFloat = 0
    @State private var hapticTrigger = 0

    /// Outer frame leaves room for the progress ring (~4pt outside the button).
    private var outerSize: CGFloat { size + 12 }
    /// Radius used for the inside-the-hit-area check. Matches the inscribed circle
    /// of the outer frame, the same shape `.contentShape(.circle)` claims for hits.
    private var hitRadius: CGFloat { outerSize / 2 }

    var body: some View {
        ZStack {
            // Button face — same composition as `CircleButton(size:, iconColor:)`
            // so the visual weight matches the surrounding row.
            Circle().fill(RemoteTheme.buttonFace)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)

            Image(systemName: "power")
                .font(.system(size: size * 0.4, weight: .heavy))
                .foregroundStyle(RemoteTheme.powerRed)

            // Progress ring — `trim(from: 0, to: 0)` already renders nothing, so no
            // explicit opacity gate needed. Starts at 12 o'clock (after -90°) and
            // sweeps clockwise as `pressProgress` animates 0 → 1.
            Circle()
                .trim(from: 0, to: pressProgress)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size + 8, height: size + 8)
        }
        .frame(width: outerSize, height: outerSize)
        .contentShape(.circle)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let inside = isInsideHitArea(value.location)
                    if pressStartTime == nil && inside {
                        // First touch — or touch back in after a drag-out.
                        startPress()
                    } else if pressStartTime != nil && !inside {
                        // Finger left the hit area — cancel anything in flight.
                        cancelPress()
                    }
                }
                .onEnded { value in
                    let inside = isInsideHitArea(value.location)
                    let started = pressStartTime != nil
                    let held = pressStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
                    let alreadyFired = longPressFired
                    cleanupPress()

                    // Suppress onTap when:
                    //  - the press was cancelled before it began (started == false), or
                    //  - the finger lifted outside the hit area (the user "slid off"), or
                    //  - the long-press already fired (don't double-dispatch).
                    guard started, inside, !alreadyFired else { return }
                    if held < longPressSeconds {
                        onTap()
                    }
                }
        )
        .sensoryFeedback(.impact(weight: .heavy), trigger: hapticTrigger)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Power")
        .accessibilityHint("Tap to toggle power. Long press for sleep timer.")
        .accessibilityAction { onTap() }
        .accessibilityAction(named: "Sleep timer") { onLongPress() }
    }

    private func isInsideHitArea(_ point: CGPoint) -> Bool {
        let dx = point.x - hitRadius
        let dy = point.y - hitRadius
        return (dx * dx + dy * dy) <= hitRadius * hitRadius
    }

    private func startPress() {
        pressStartTime = .now
        longPressFired = false
        withAnimation(.linear(duration: longPressSeconds)) {
            pressProgress = 1
        }
        longPressTimer = Task {
            try? await Task.sleep(for: .seconds(longPressSeconds))
            if Task.isCancelled { return }
            longPressFired = true
            hapticTrigger &+= 1
            onLongPress()
        }
    }

    private func cancelPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
        pressStartTime = nil
        withAnimation(.easeOut(duration: 0.2)) {
            pressProgress = 0
        }
    }

    private func cleanupPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
        pressStartTime = nil
        withAnimation(.easeOut(duration: 0.2)) {
            pressProgress = 0
        }
    }
}
