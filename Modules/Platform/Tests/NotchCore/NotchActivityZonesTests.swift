import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct NotchActivityZonesTests {
    /// A 185 × 32 hardware notch at the top of a display whose top edge is at y = 982.
    private let closed = CGRect(x: 663.5, y: 950, width: 185, height: 32)

    private func zone(_ x: CGFloat, _ y: CGFloat) -> NotchActivityZone {
        NotchActivityZones.zone(of: CGPoint(x: x, y: y), closedRect: closed, sideWidth: 44, bottomHeight: 8, padding: 4)
    }

    @Test func theMiddleOfTheNotchOpensIt() {
        #expect(zone(756, 970) == .middle)
        // The top edge of the screen above the camera too.
        #expect(zone(756, 982) == .middle)
        #expect(zone(664, 951) == .middle)
    }

    @Test func theSidesBelongToTheActivity() {
        #expect(zone(640, 970) == .own)
        #expect(zone(870, 970) == .own)
        // Right at the top edge, as a pointer thrown up to the menu bar lands.
        #expect(zone(640, 982) == .own)
    }

    @Test func theStripUnderTheCameraBelongsToTheActivity() {
        #expect(zone(756, 945) == .own)
        #expect(zone(756, 943) == .own)
    }

    @Test func theInteractionPaddingCountsAsTheActivitysToo() {
        // Just past the side and just under the strip.
        #expect(zone(617, 970) == .own)
        #expect(zone(756, 939) == .own)
    }

    @Test func pastThePaddingIsOutside() {
        #expect(zone(614, 970) == .outside)
        #expect(zone(756, 936) == .outside)
        #expect(zone(900, 970) == .outside)
    }

    @Test func withoutAStripTheMiddleReachesTheNotchsBottom() {
        let below = NotchActivityZones.zone(
            of: CGPoint(x: 756, y: 948), closedRect: closed, sideWidth: 44, bottomHeight: 0, padding: 4)
        #expect(below == .middle)
    }
}
