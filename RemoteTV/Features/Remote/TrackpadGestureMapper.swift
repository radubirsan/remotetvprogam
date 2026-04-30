import CoreGraphics

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
