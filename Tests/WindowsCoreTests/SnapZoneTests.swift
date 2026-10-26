import CoreGraphics
import Foundation
import Testing
@testable import WindowsCore

@Suite struct SnapZoneTests {
    /// The usable area of a 1512×982 display below a 33 pt menu bar, with a Dock 70 pt high.
    private let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)

    @Test func halvesSplitTheVisibleArea() {
        #expect(SnapZone.leftHalf.frame(in: visible) == CGRect(x: 0, y: 70, width: 756, height: 879))
        #expect(SnapZone.rightHalf.frame(in: visible) == CGRect(x: 756, y: 70, width: 756, height: 879))
        // AppKit's origin is at the bottom: the top half has the larger y.
        #expect(SnapZone.topHalf.frame(in: visible) == CGRect(x: 0, y: 509.5, width: 1512, height: 439.5))
        #expect(SnapZone.bottomHalf.frame(in: visible) == CGRect(x: 0, y: 70, width: 1512, height: 439.5))
    }

    @Test func quartersTakeACornerEach() {
        #expect(SnapZone.topLeft.frame(in: visible) == CGRect(x: 0, y: 509.5, width: 756, height: 439.5))
        #expect(SnapZone.topRight.frame(in: visible) == CGRect(x: 756, y: 509.5, width: 756, height: 439.5))
        #expect(SnapZone.bottomLeft.frame(in: visible) == CGRect(x: 0, y: 70, width: 756, height: 439.5))
        #expect(SnapZone.bottomRight.frame(in: visible) == CGRect(x: 756, y: 70, width: 756, height: 439.5))
    }

    @Test func maximizeFillsAndCenterKeepsTwoThirds() {
        #expect(SnapZone.maximize.frame(in: visible) == visible)
        let center = SnapZone.center.frame(in: visible)
        #expect(center.width == 1008)
        #expect(center.height == 586)
        #expect(center.midX == visible.midX)
        #expect(center.midY == visible.midY)
    }

    @Test func zonesWorkOnADisplayPlacedElsewhere() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1055)
        #expect(SnapZone.rightHalf.frame(in: second) == CGRect(x: 2472, y: -200, width: 960, height: 1055))
    }

    @Test func convertsToTheTopLeftCoordinatesWindowsAreMovedIn() {
        // A window whose top edge touches the menu bar of the primary display (982 pt high).
        let frame = CGRect(x: 0, y: 70, width: 756, height: 879)
        #expect(SnapGeometry.topLeftOrigin(of: frame, primaryScreenHeight: 982) == CGPoint(x: 0, y: 33))
        // On a display below the primary one, y grows past the primary height.
        let lower = CGRect(x: 100, y: -500, width: 400, height: 300)
        #expect(SnapGeometry.topLeftOrigin(of: lower, primaryScreenHeight: 982) == CGPoint(x: 100, y: 1182))
    }

    @Test func picksTheDisplayHoldingMostOfTheWindow() {
        let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        #expect(SnapGeometry.displayIndex(for: CGRect(x: 100, y: 100, width: 500, height: 400), among: displays) == 0)
        #expect(SnapGeometry.displayIndex(for: CGRect(x: 1400, y: 100, width: 500, height: 400), among: displays) == 1)
        // A window off every display goes to the first one.
        #expect(SnapGeometry.displayIndex(for: CGRect(x: 9000, y: 9000, width: 10, height: 10), among: displays) == 0)
        #expect(SnapGeometry.displayIndex(for: .zero, among: []) == nil)
    }

    @Test func everyZoneHasADistinctDefaultShortcut() {
        let shortcuts = SnapZone.allCases.map(\.shortcut)
        #expect(Set(shortcuts.map(\.keyCode)).count == SnapZone.allCases.count)
        #expect(shortcuts.allSatisfy { $0.modifiers == [.control, .option] })
        #expect(SnapZone.leftHalf.shortcut.keyCode == 123)
        #expect(SnapZone.maximize.shortcut.keyCode == 36)
        #expect(SnapZone.leftHalf.shortcut.display == "⌃⌥←")
    }

    @Test func snappingIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = WindowSettingsStore(defaults: defaults)
        #expect(store.snapEnabled == false)
        store.snapEnabled = true
        #expect(WindowSettingsStore(defaults: defaults).snapEnabled == true)
    }
}
