import Foundation
import Testing
@testable import NotchCore

@Suite struct WheelRedirectTests {
    @Test func aMouseWheelTurnedUpOrDownMovesASidewaysRowAlong() {
        // A wheel has no phases of touch; its vertical turn becomes the row's horizontal travel.
        #expect(WheelRedirect.sideways(deltaX: 0, deltaY: -3, isTouch: false) == -3)
        #expect(WheelRedirect.sideways(deltaX: 0, deltaY: 2.5, isTouch: false) == 2.5)
    }

    @Test func aTrackpadIsLeftAlone() {
        // Fingers already scroll sideways by moving sideways.
        #expect(WheelRedirect.sideways(deltaX: 0, deltaY: -3, isTouch: true) == nil)
    }

    @Test func aWheelThatAlreadyScrollsSidewaysIsLeftAlone() {
        // A tilt wheel, or Shift held: the sideways part is the larger one.
        #expect(WheelRedirect.sideways(deltaX: 4, deltaY: 1, isTouch: false) == nil)
        #expect(WheelRedirect.sideways(deltaX: 0, deltaY: 0, isTouch: false) == nil)
    }
}
