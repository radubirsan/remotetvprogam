import CoreGraphics
import Foundation
import Testing
@testable import RemoteTV

struct TrackpadGestureMapperTests {
    @Test func zeroTranslationIsTap() {
        #expect(TrackpadGestureMapper.gesture(for: .zero) == .tap)
    }

    @Test func smallTranslationIsTap() {
        let translation = CGSize(width: 5, height: 4)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .tap)
    }

    @Test func translationJustBelowThresholdIsTap() {
        let translation = CGSize(width: 27, height: 0)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .tap)
    }

    @Test func translationAtThresholdIsSwipe() {
        let threshold = TrackpadGestureMapper.defaultThreshold
        let translation = CGSize(width: threshold, height: 0)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.right))
    }

    @Test func swipeRightMapsToRightCommand() {
        let translation = CGSize(width: 60, height: 5)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.right))
    }

    @Test func swipeLeftMapsToLeftCommand() {
        let translation = CGSize(width: -60, height: 5)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.left))
    }

    @Test func swipeDownMapsToDownCommand() {
        let translation = CGSize(width: 5, height: 60)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.down))
    }

    @Test func swipeUpMapsToUpCommand() {
        let translation = CGSize(width: 5, height: -60)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.up))
    }

    @Test func diagonalDominantHorizontalPicksHorizontalAxis() {
        let translation = CGSize(width: 50, height: 40)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.right))
    }

    @Test func diagonalDominantVerticalPicksVerticalAxis() {
        let translation = CGSize(width: 40, height: 50)
        #expect(TrackpadGestureMapper.gesture(for: translation) == .swipe(.down))
    }

    @Test func customThresholdIsHonored() {
        let translation = CGSize(width: 50, height: 0)
        #expect(TrackpadGestureMapper.gesture(for: translation, threshold: 100) == .tap)
        #expect(TrackpadGestureMapper.gesture(for: translation, threshold: 25) == .swipe(.right))
    }
}

struct JogWheelTrackerTests {
    /// Feeds an arc of `sweep` radians (sampled every ~`step`) at fixed radius into the
    /// tracker and returns the summed signed detents. Screen coords: y points down, so an
    /// increasing angle traces a clockwise path.
    private func feedArc(
        into tracker: inout JogWheelTracker,
        sweep: Double,
        step: Double = .pi / 18,        // 10°
        radius: CGFloat = 100,
        center: CGPoint = CGPoint(x: 150, y: 150)
    ) -> Int {
        var total = 0
        let steps = Int((abs(sweep) / step).rounded())
        let direction = sweep < 0 ? -1.0 : 1.0
        for i in 0...steps {
            let theta = direction * step * Double(i)
            let p = CGPoint(x: center.x + radius * CGFloat(cos(theta)),
                            y: center.y + radius * CGFloat(sin(theta)))
            total += tracker.update(location: p)
        }
        return total
    }

    @Test func clockwiseFullCircleStepsVolumeUp() {
        var tracker = JogWheelTracker()
        let total = feedArc(into: &tracker, sweep: 2 * .pi)
        #expect(tracker.isEngaged)
        #expect(total >= 8)            // ~10 detents/revolution, minus startup samples
    }

    @Test func counterClockwiseFullCircleStepsVolumeDown() {
        var tracker = JogWheelTracker()
        let total = feedArc(into: &tracker, sweep: -2 * .pi)
        #expect(tracker.isEngaged)
        #expect(total <= -8)
    }

    @Test func straightSwipeNeverEngages() {
        var tracker = JogWheelTracker()
        var total = 0
        // A long straight horizontal drag: constant heading, zero curvature.
        for x in stride(from: 40.0, through: 260.0, by: 8.0) {
            total += tracker.update(location: CGPoint(x: x, y: 150))
        }
        #expect(!tracker.isEngaged)
        #expect(total == 0)
    }

    @Test func tapProducesNoDetents() {
        var tracker = JogWheelTracker()
        let p = CGPoint(x: 150, y: 150)
        #expect(tracker.update(location: p) == 0)
        #expect(tracker.update(location: p) == 0)
        #expect(!tracker.isEngaged)
    }

    @Test func quarterTurnEngagesAndFiresFirstDetent() {
        var tracker = JogWheelTracker()
        // 90° clockwise clears the 60° activation and the first 36° detent.
        let total = feedArc(into: &tracker, sweep: .pi / 2)
        #expect(tracker.isEngaged)
        #expect(total >= 1)
    }

    @Test func reversingDirectionStepsVolumeBackDown() {
        var tracker = JogWheelTracker()
        let up = feedArc(into: &tracker, sweep: 2 * .pi)         // wind clockwise
        #expect(up > 0)
        // Now unwind counter-clockwise from where we are: detents come back the other way.
        var down = 0
        let center = CGPoint(x: 150, y: 150)
        let radius: CGFloat = 100
        let step = Double.pi / 18
        let startSteps = Int((2 * Double.pi / step).rounded())
        for i in stride(from: startSteps, through: 0, by: -1) {
            let theta = step * Double(i)
            let p = CGPoint(x: center.x + radius * CGFloat(cos(theta)),
                            y: center.y + radius * CGFloat(sin(theta)))
            down += tracker.update(location: p)
        }
        #expect(down < 0)
    }
}
