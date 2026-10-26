import Testing
@testable import NotchCore

@Suite struct SwipeAccumulatorTests {
    @Test func belowThresholdEmitsNothing() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -10, deltaY: 0, phase: .began) == nil)
        #expect(swipe.add(deltaX: -20, deltaY: 0, phase: .changed) == nil)
    }

    @Test func swipeLeftEmitsNext() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -10, deltaY: 0, phase: .began) == nil)
        #expect(swipe.add(deltaX: -30, deltaY: 0, phase: .changed) == .next)
    }

    @Test func swipeRightEmitsPrevious() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: 15, deltaY: 0, phase: .began) == nil)
        #expect(swipe.add(deltaX: 30, deltaY: 0, phase: .changed) == .previous)
    }

    @Test func emitsOnlyOncePerGesture() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -50, deltaY: 0, phase: .began) == .next)
        #expect(swipe.add(deltaX: -100, deltaY: 0, phase: .changed) == nil)
    }

    @Test func newGestureCanEmitAgain() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -50, deltaY: 0, phase: .began) == .next)
        #expect(swipe.add(deltaX: 0, deltaY: 0, phase: .ended) == nil)
        #expect(swipe.add(deltaX: -50, deltaY: 0, phase: .began) == .next)
    }

    @Test func endedResetsPartialProgress() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -30, deltaY: 0, phase: .began) == nil)
        #expect(swipe.add(deltaX: 0, deltaY: 0, phase: .ended) == nil)
        #expect(swipe.add(deltaX: -30, deltaY: 0, phase: .changed) == nil)
    }

    @Test func cancelledResetsPartialProgress() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -30, deltaY: 0, phase: .began) == nil)
        #expect(swipe.add(deltaX: 0, deltaY: 0, phase: .cancelled) == nil)
        #expect(swipe.add(deltaX: -30, deltaY: 0, phase: .changed) == nil)
    }

    @Test func verticalScrollIsIgnored() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -45, deltaY: 80, phase: .began) == nil)
    }

    @Test func momentumAfterGestureDoesNotEmit() {
        var swipe = SwipeAccumulator()
        #expect(swipe.add(deltaX: -50, deltaY: 0, phase: .began) == .next)
        #expect(swipe.add(deltaX: 0, deltaY: 0, phase: .ended) == nil)
        for _ in 0..<3 {
            #expect(swipe.add(deltaX: -60, deltaY: 0, phase: .momentum) == nil)
        }
    }
}
