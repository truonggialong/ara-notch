import CoreGraphics
import Testing
@testable import ClipboardCore

@Suite struct PanelPlacementTests {
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    private let size = CGSize(width: 560, height: 380)

    @Test func placesBelowRightOfCursor() {
        let frame = PanelPlacement.frame(size: size, near: CGPoint(x: 400, y: 700), in: visible)
        #expect(frame == CGRect(x: 412, y: 308, width: 560, height: 380))
    }

    @Test func shiftsLeftAtRightEdge() {
        let frame = PanelPlacement.frame(size: size, near: CGPoint(x: 1500, y: 700), in: visible)
        #expect(frame.maxX == 1512)
        #expect(frame.size == size)
    }

    @Test func shiftsUpAtBottomEdge() {
        let frame = PanelPlacement.frame(size: size, near: CGPoint(x: 400, y: 100), in: visible)
        #expect(frame.minY == 0)
    }

    @Test func staysInsideAtTopLeft() {
        let frame = PanelPlacement.frame(size: size, near: CGPoint(x: 0, y: 950), in: visible)
        #expect(visible.contains(frame))
    }

    @Test func worksOnScreenWithNegativeOrigin() {
        let secondary = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let frame = PanelPlacement.frame(size: size, near: CGPoint(x: -10, y: 150), in: secondary)
        #expect(secondary.contains(frame))
    }

    @Test func pinsTopLeftWhenPanelIsLargerThanScreen() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let frame = PanelPlacement.frame(size: size, near: CGPoint(x: 200, y: 150), in: small)
        #expect(frame.minX == 0)
        #expect(frame.maxY == 300)
    }
}
