import CoreGraphics
import Testing
@testable import WindowsCore

@Suite struct EdgeSnapTests {
    /// A 1512×982 display; AppKit coordinates, origin bottom-left.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func zone(_ x: CGFloat, _ y: CGFloat) -> SnapZone? {
        EdgeSnap.zone(at: CGPoint(x: x, y: y), in: screen)
    }

    @Test func theMiddleOfTheScreenSnapsNothing() {
        #expect(zone(700, 500) == nil)
        #expect(zone(30, 500) == nil)
    }

    @Test func sideEdgesGiveHalves() {
        #expect(zone(0, 500) == .leftHalf)
        #expect(zone(5, 500) == .leftHalf)
        #expect(zone(1511, 500) == .rightHalf)
    }

    @Test func theTopEdgeMaximizes() {
        #expect(zone(700, 981) == .maximize)
        #expect(zone(700, 978) == .maximize)
    }

    @Test func cornersGiveQuarters() {
        #expect(zone(2, 980) == .topLeft)
        #expect(zone(1510, 980) == .topRight)
        #expect(zone(2, 3) == .bottomLeft)
        #expect(zone(1510, 3) == .bottomRight)
        // Near a corner along the side edge counts as the corner too.
        #expect(zone(2, 900) == .topLeft)
        #expect(zone(1510, 60) == .bottomRight)
    }

    @Test func theBottomEdgeAloneSnapsNothing() {
        // The Dock lives there.
        #expect(zone(700, 2) == nil)
    }

    @Test func worksOnADisplayPlacedElsewhere() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        #expect(EdgeSnap.zone(at: CGPoint(x: 1514, y: 300), in: second) == .leftHalf)
        #expect(EdgeSnap.zone(at: CGPoint(x: 3430, y: 878), in: second) == .topRight)
        #expect(EdgeSnap.zone(at: CGPoint(x: 100, y: 300), in: second) == nil)
    }

    @Test func aWindowCountsAsDraggedOnceItHasMoved() {
        let start = CGPoint(x: 100, y: 100)
        #expect(!EdgeSnap.hasMoved(from: start, to: CGPoint(x: 102, y: 101)))
        #expect(EdgeSnap.hasMoved(from: start, to: CGPoint(x: 120, y: 100)))
    }

    @Test func edgeSnappingFollowsItsOwnSwitch() {
        let defaults = InMemoryDefaults()
        let store = WindowSettingsStore(defaults: defaults)
        #expect(store.edgeSnapEnabled == false)
        store.edgeSnapEnabled = true
        #expect(WindowSettingsStore(defaults: defaults).edgeSnapEnabled == true)
    }
}
