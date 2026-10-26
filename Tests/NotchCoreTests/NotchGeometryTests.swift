import CoreGraphics
import Testing
@testable import NotchCore

private let notched = ScreenDescriptor(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    safeAreaTop: 32, auxLeftWidth: 663.5, auxRightWidth: 663.5, menuBarHeight: 32)
private let plain = ScreenDescriptor(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    safeAreaTop: 0, auxLeftWidth: nil, auxRightWidth: nil, menuBarHeight: 25)

@Suite struct NotchGeometryTests {
    @Test func physicalNotchClosedRect() {
        let g = NotchGeometry(screen: notched)
        #expect(g.hasPhysicalNotch)
        #expect(g.closedRect == CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }

    @Test func virtualNotchClosedRect() {
        let g = NotchGeometry(screen: plain)
        #expect(!g.hasPhysicalNotch)
        #expect(g.closedRect == CGRect(x: 1190, y: 1415, width: 180, height: 25))
    }

    @Test func virtualNotchUsesMinimumHeightWhenMenuBarHidden() {
        var s = plain
        s.menuBarHeight = 0
        #expect(NotchGeometry(screen: s).closedRect == CGRect(x: 1190, y: 1416, width: 180, height: 24))
    }

    @Test func withNoHardwareNotchTheNotchWaitsAsAThinBarOnTheTopEdge() {
        // Nothing is cut out of this display, so the waiting notch takes hardly any of the
        // menu bar: 150 by 10, in the middle of the top edge.
        let g = NotchGeometry(screen: plain)
        #expect(g.idleRect == CGRect(x: 1205, y: 1430, width: 150, height: 10))
        #expect(g.restsAsBar)
    }

    @Test func aHardwareNotchAndAFloatingPillWaitAtTheirOwnSize() {
        let hardware = NotchGeometry(screen: notched)
        #expect(hardware.idleRect == hardware.closedRect)
        #expect(!hardware.restsAsBar)
        let pill = NotchGeometry(screen: plain, style: .pill)
        #expect(pill.idleRect == pill.closedRect)
        #expect(!pill.restsAsBar)
    }

    @Test func theWaitingBarIsReachedOnlyOnTheBarAndTheWokenNotchOverItsFullSize() {
        let g = NotchGeometry(screen: plain)
        // Asleep: the bar and four points round it. A pointer on the menu bar under it is not on it.
        #expect(g.hoverRect(padding: 4, isAwake: false) == CGRect(x: 1201, y: 1426, width: 158, height: 18))
        #expect(!g.hoverRect(padding: 4, isAwake: false).contains(CGPoint(x: 1280, y: 1420)))
        // Awake (touched, or showing something): the whole notch, as before.
        #expect(g.hoverRect(padding: 4, isAwake: true) == g.hoverRect(padding: 4))
        #expect(g.hoverRect(padding: 4, isAwake: true).contains(CGPoint(x: 1280, y: 1420)))
        // Waking never lets go of a pointer that woke it.
        #expect(g.hoverRect(padding: 4, isAwake: true).contains(g.hoverRect(padding: 4, isAwake: false)))
    }

    @Test func aHardwareNotchIsReachedTheSameAsleepOrAwake() {
        let g = NotchGeometry(screen: notched)
        #expect(g.hoverRect(padding: 4, isAwake: false) == g.hoverRect(padding: 4, isAwake: true))
    }

    @Test func safeAreaWithoutAuxAreasIsNotAPhysicalNotch() {
        var s = notched
        s.auxLeftWidth = nil
        #expect(!NotchGeometry(screen: s).hasPhysicalNotch)
    }

    @Test func filesBeingDraggedOpenTheNotchFromWellBelowTheScreensEdge() {
        // The top edge of the screen is where macOS starts Mission Control during a drag, so
        // the notch answers a drag from further out: 80 points to each side, 64 below.
        let geometry = NotchGeometry(screen: notched)
        #expect(geometry.dragRect == CGRect(x: 583.5, y: 886, width: 345, height: 96))
        #expect(geometry.dragRect.contains(CGPoint(x: 756, y: 900)))
        #expect(!geometry.hoverRect.contains(CGPoint(x: 756, y: 900)))
        // It still reaches the top edge itself.
        #expect(geometry.dragRect.maxY == geometry.closedRect.maxY)
    }

    @Test func hoverRectPadsAllSides() {
        #expect(NotchGeometry(screen: notched).hoverRect == CGRect(x: 659.5, y: 946, width: 193, height: 40))
    }

    @Test func openRectIsCenteredOnNotchAndPinnedToTop() {
        #expect(NotchGeometry(screen: notched).openRect() == CGRect(x: 436, y: 782, width: 640, height: 200))
    }

    @Test func openHitRectExtendsAboveTop() {
        #expect(NotchGeometry(screen: notched).openHitRect() == CGRect(x: 436, y: 782, width: 640, height: 204))
    }

    @Test func aPanelThatShrinksCanLeaveThePointerOutside() {
        let g = NotchGeometry(screen: notched)
        let tall = CGSize(width: 640, height: 500)
        let low = CGSize(width: 640, height: 232)
        // On a chip near the foot of the tall panel: 400 points below the screen's top.
        #expect(g.shrinkingLeavesOutside(CGPoint(x: 756, y: 582), from: tall, to: low))
        // Near the top, the pointer is inside both.
        #expect(!g.shrinkingLeavesOutside(CGPoint(x: 756, y: 900), from: tall, to: low))
        // Already outside the tall panel: the pointer had left by itself.
        #expect(!g.shrinkingLeavesOutside(CGPoint(x: 100, y: 582), from: tall, to: low))
        // A panel that grows leaves no one outside.
        #expect(!g.shrinkingLeavesOutside(CGPoint(x: 756, y: 582), from: low, to: tall))
    }

    @Test func headerRectIsTheTopStripOfTheOpenPanel() {
        #expect(NotchGeometry(screen: notched).headerRect() == CGRect(x: 436, y: 950, width: 640, height: 32))
        #expect(NotchGeometry(screen: plain).headerRect().height == 25)
    }

    @Test func compactRectWidensTheNotchOnBothSides() {
        #expect(NotchGeometry(screen: notched).compactRect() == CGRect(x: 571.5, y: 950, width: 369, height: 32))
        #expect(NotchGeometry(screen: plain).compactRect(sideWidth: 50) == CGRect(x: 1140, y: 1415, width: 280, height: 25))
    }

    @Test func openRectOnSecondaryScreenWithNegativeOrigin() {
        var s = plain
        s.frame.origin = CGPoint(x: -2560, y: 200)
        let g = NotchGeometry(screen: s)
        #expect(g.closedRect == CGRect(x: -1370, y: 1615, width: 180, height: 25))
        #expect(g.openRect() == CGRect(x: -1600, y: 1440, width: 640, height: 200))
    }

    @Test func openRectClampsWhenNotchIsOffCenter() {
        let s = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
            safeAreaTop: 30, auxLeftWidth: 50, auxRightWidth: 750, menuBarHeight: 30)
        #expect(NotchGeometry(screen: s).openRect().minX == 0)
    }

    @Test func openRectPinsLeftWhenScreenNarrowerThanPanel() {
        var s = plain
        s.frame = CGRect(x: 100, y: 0, width: 500, height: 400)
        let r = NotchGeometry(screen: s).openRect()
        #expect(r.minX == 100)
        #expect(r.maxY == 400)
    }

    @Test func theInteractionAreaGrowsWithItsPadding() {
        let geometry = NotchGeometry(screen: notched)
        #expect(geometry.hoverRect(padding: 0) == geometry.closedRect)
        #expect(geometry.hoverRect(padding: 10) == geometry.closedRect.insetBy(dx: -10, dy: -10))
        #expect(geometry.hoverRect(padding: -5) == geometry.closedRect)
        #expect(geometry.hoverRect == geometry.hoverRect(padding: NotchGeometry.hoverPadding))
    }
}

@Suite struct PillGeometryTests {
    private let pill = NotchGeometry(screen: plain, style: .pill)

    @Test func thePillFloatsBelowTheMenuBar() {
        #expect(pill.isPill)
        #expect(pill.closedRect == CGRect(x: 1190, y: 1379, width: 180, height: 30))
    }

    @Test func theOpenPanelGrowsDownFromThePillsTop() {
        #expect(pill.openRect() == CGRect(x: 960, y: 1209, width: 640, height: 200))
        #expect(pill.headerRect() == CGRect(x: 960, y: 1379, width: 640, height: 30))
    }

    @Test func aLiveActivityWidensThePillInPlace() {
        #expect(pill.compactRect(sideWidth: 50) == CGRect(x: 1140, y: 1379, width: 280, height: 30))
    }

    @Test func aDisplayWithARealNotchIgnoresThePillStyle() {
        let geometry = NotchGeometry(screen: notched, style: .pill)
        #expect(!geometry.isPill)
        #expect(geometry.closedRect == NotchGeometry(screen: notched).closedRect)
        #expect(geometry.openRect() == NotchGeometry(screen: notched).openRect())
    }

    @Test func theAttachedStyleIsTheDefault() {
        #expect(!NotchGeometry(screen: plain).isPill)
        #expect(NotchGeometry(screen: plain).closedRect.maxY == 1440)
    }
}

@Suite struct PillSettingTests {
    @Test func thePillStyleIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        #expect(store.pillStyle == false)
        store.pillStyle = true
        #expect(ShellSettingsStore(defaults: defaults).pillStyle == true)
    }
}
