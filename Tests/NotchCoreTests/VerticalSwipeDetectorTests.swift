import Testing
@testable import NotchCore

@Suite struct VerticalSwipeDetectorTests {
    @Test func fingersMovingDownFarEnoughFireOnce() {
        var detector = VerticalSwipeDetector(threshold: 30)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 10, phase: .began) == nil)
        #expect(detector.add(deltaX: 1, fingerDeltaY: 15, phase: .changed) == nil)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 8, phase: .changed) == .down)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 40, phase: .changed) == nil)
    }

    @Test func fingersMovingUpFireUp() {
        var detector = VerticalSwipeDetector(threshold: 30)
        #expect(detector.add(deltaX: 0, fingerDeltaY: -20, phase: .began) == nil)
        #expect(detector.add(deltaX: 0, fingerDeltaY: -20, phase: .changed) == .up)
    }

    @Test func aMostlySidewaysGestureDoesNotFire() {
        var detector = VerticalSwipeDetector(threshold: 30)
        #expect(detector.add(deltaX: 50, fingerDeltaY: 20, phase: .began) == nil)
        #expect(detector.add(deltaX: 50, fingerDeltaY: 20, phase: .changed) == nil)
    }

    @Test func aNewGestureCanFireAgain() {
        var detector = VerticalSwipeDetector(threshold: 30)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 40, phase: .began) == .down)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 0, phase: .ended) == nil)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 40, phase: .began) == .down)
    }

    @Test func coastingAfterTheFingersLiftIsIgnored() {
        var detector = VerticalSwipeDetector(threshold: 30)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 10, phase: .began) == nil)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 100, phase: .momentum) == nil)
    }

    @Test func aMouseWheelNotchFiresAtOnceInItsDirection() {
        var detector = VerticalSwipeDetector(threshold: 30)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 1, phase: .wheel) == .down)
        #expect(detector.add(deltaX: 0, fingerDeltaY: -1, phase: .wheel) == .up)
        #expect(detector.add(deltaX: 0, fingerDeltaY: 0, phase: .wheel) == nil)
    }

    @Test func sensitivityMapsToADistance() {
        #expect(SwipeSensitivity.low.threshold > SwipeSensitivity.medium.threshold)
        #expect(SwipeSensitivity.medium.threshold > SwipeSensitivity.high.threshold)
        #expect(SwipeSensitivity.allCases.count == 3)
    }

    @Test func fingerDirectionAccountsForNaturalScrolling() {
        // With natural scrolling the system reports the fingers' own direction.
        #expect(VerticalSwipeDetector.fingerDelta(scrollingDeltaY: 12, isNatural: true) == 12)
        #expect(VerticalSwipeDetector.fingerDelta(scrollingDeltaY: 12, isNatural: false) == -12)
    }
}
