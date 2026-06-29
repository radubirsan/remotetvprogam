import CoreGraphics
import Foundation
import RemoteTVCore

/// Logical outcome of a single trackpad gesture: either a stationary tap (mapped to
/// `KEY_ENTER` by the view) or a swipe in one of the four cardinal directions
/// (mapped to the matching `KEY_LEFT`/`KEY_RIGHT`/`KEY_UP`/`KEY_DOWN`).
enum TrackpadGesture: Equatable {
    case tap
    case swipe(TVCommand)
}

/// Pure mapping from a `DragGesture` translation to a ``TrackpadGesture``. Lives outside
/// the SwiftUI view so the classification rules are unit-testable without driving a
/// gesture recognizer.
enum TrackpadGestureMapper {
    /// Distance in points the finger must travel before a drag is treated as a swipe
    /// rather than a tap. Picked small enough that intentional swipes register reliably,
    /// large enough that the unavoidable jitter of a normal tap doesn't fire a direction.
    static let defaultThreshold: CGFloat = 28

    static func gesture(
        for translation: CGSize,
        threshold: CGFloat = defaultThreshold
    ) -> TrackpadGesture {
        let dx = translation.width
        let dy = translation.height
        let absX = abs(dx)
        let absY = abs(dy)
        guard max(absX, absY) >= threshold else {
            return .tap
        }
        if absX >= absY {
            return .swipe(dx > 0 ? .right : .left)
        } else {
            return .swipe(dy > 0 ? .down : .up)
        }
    }
}

/// Stateful tracker that turns a continuous drag path into "jog wheel" detents — like an
/// iPod click wheel laid over the trackpad. Holding down and circling spins the wheel and
/// steps the TV volume: clockwise = up, counter-clockwise = down.
///
/// It accumulates the **curvature** of the finger path — how much the *direction of travel*
/// rotates from one sample to the next — rather than the angle around a centre. That's what
/// separates a spin from an ordinary swipe **without** the wheel's geometry: a straight swipe
/// keeps a constant heading (≈0 curvature) and never engages, while circling rotates the
/// heading steadily. A chord swipe that happens to sweep a wide angle *around* the centre
/// would fool an angle-around-centre tracker; it can't fool this one.
///
/// Sign convention is screen space (y points down), so a clockwise turn is positive and maps
/// to volume *up*; counter-clockwise is negative and maps to volume *down*.
///
/// Pure value type so the rules are unit-testable without a gesture recognizer: the view owns
/// one instance per drag and feeds it `update(location:)`.
struct JogWheelTracker {
    /// Curvature (radians) the path must turn through before the wheel engages. A swipe's
    /// incidental wobble stays well under this; a deliberate arc clears it in a quarter turn.
    var activationCurvature: Double = .pi / 3        // 60°
    /// Curvature between volume detents once engaged. A full revolution (2π) ≈ 10 steps.
    var detentCurvature: Double = .pi / 5            // 36°
    /// Minimum finger move (points) for a sample to count — filters jitter whose heading is
    /// pure noise.
    var minMove: CGFloat = 3
    /// Largest single-step heading turn accepted; bigger jumps are treated as noise or a
    /// discontinuity (a sharp corner / sensor skip) rather than real rotation.
    var maxStepTurn: Double = .pi / 2                // 90°

    /// Net signed curvature so far (radians) — drives the wheel's visual rotation.
    private(set) var curvature: Double = 0
    /// True once the path has curved past ``activationCurvature``; stays true until reset.
    /// While true the view suppresses the trailing tap/swipe.
    private(set) var isEngaged: Bool = false

    private var lastPoint: CGPoint?
    private var lastHeading: Double?
    private var detentsFired: Int = 0

    /// Feed the next finger location (the wheel's local coordinates). Returns the signed
    /// number of volume detents to fire this step: `+n` → n× volume-up (clockwise), `-n` →
    /// n× volume-down (counter-clockwise), `0` → nothing yet. Read ``curvature`` afterwards
    /// for the visual rotation and ``isEngaged`` to decide whether to swallow the tap/swipe.
    mutating func update(location: CGPoint) -> Int {
        defer { lastPoint = location }
        guard let prev = lastPoint else { return 0 }
        let dx = Double(location.x - prev.x)
        let dy = Double(location.y - prev.y)
        guard (dx * dx + dy * dy).squareRoot() >= Double(minMove) else { return 0 }

        let heading = atan2(dy, dx)
        defer { lastHeading = heading }
        guard let last = lastHeading else { return 0 }

        var turn = heading - last
        if turn > .pi { turn -= 2 * .pi } else if turn <= -.pi { turn += 2 * .pi }
        guard abs(turn) <= maxStepTurn else { return 0 }

        curvature += turn
        if !isEngaged && abs(curvature) >= activationCurvature { isEngaged = true }
        guard isEngaged else { return 0 }

        // Detents are measured from zero curvature, so reversing direction (even back through
        // zero into the opposite sign) fires the right count the other way.
        let target = Int((curvature / detentCurvature).rounded(.towardZero))
        let diff = target - detentsFired
        detentsFired = target
        return diff
    }
}
