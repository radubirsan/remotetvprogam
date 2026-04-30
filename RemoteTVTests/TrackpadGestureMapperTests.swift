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
