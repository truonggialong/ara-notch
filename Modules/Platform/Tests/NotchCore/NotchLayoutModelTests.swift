import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct NotchLayoutModelTests {
    @Test func lessTransparencyAskedForGivesPlainBlack() {
        #expect(NotchMaterial.glass.shown(reduceTransparency: true) == .black)
        #expect(NotchMaterial.liquid.shown(reduceTransparency: false) == .liquid)
        #expect(NotchMaterial.glass.shade(increasedContrast: true) > NotchMaterial.glass.shade(increasedContrast: false))
    }

    @Test func theNotchGrowsWithABounceAndShrinksWithout() {
        #expect(NotchMotion.spring(growing: true).bounce > 0)
        #expect(NotchMotion.spring(growing: false).bounce == 0)
        #expect(NotchMotion.shrink.duration < NotchMotion.grow.duration)
    }

    @Test func theStandardButtonsAreExploreTimerSettingsPinAndMusic() {
        let layout = OrbitLayout(stored: nil)
        #expect(layout == .standard)
        #expect(layout.actions[.left0] == .explore)
        #expect(layout.actions[.bottom0] == .page("media"))
        #expect(layout.usesBottom)
    }

    @Test func buttonsSurviveARoundTripThroughTheSettings() {
        var layout = OrbitLayout.standard
        layout.swap(.left1, .right2)
        layout.set(.page("notes"), at: .bottom1)
        #expect(OrbitLayout(stored: layout.stored) == layout)
        #expect(layout.actions[.left1] == nil)
        #expect(layout.actions[.right2] == .page("timer"))
    }

    @Test func whatIsNotUnderstoodIsLeftOutAndAnEmptyListMeansNoButtons() {
        let layout = OrbitLayout(stored: ["left0=explore", "nowhere=pin", "right0=dance", "right1=page:"])
        #expect(layout.actions == [.left0: .explore])
        #expect(OrbitLayout(stored: []).actions.isEmpty)
        #expect(!OrbitLayout(stored: []).usesBottom)
    }

    @Test func buttonsStandOutsideTheNotchOnItsSidesAndBelowIt() {
        let size = CGSize(width: 400, height: 172)
        let left = OrbitLayout.centre(of: .left0, openSize: size, scale: 1)
        let right = OrbitLayout.centre(of: .right1, openSize: size, scale: 1)
        let bottom = OrbitLayout.centre(of: .bottom0, openSize: size, scale: 1)
        #expect(left.x + OrbitLayout.diameter / 2 <= -OrbitLayout.gap + 0.01)
        #expect(right.x - OrbitLayout.diameter / 2 >= size.width + OrbitLayout.gap - 0.01)
        #expect(right.y > OrbitLayout.centre(of: .right0, openSize: size, scale: 1).y)
        #expect(bottom.y - OrbitLayout.diameter / 2 >= size.height)
    }

    @Test func aPageOpensAtItsOwnSheetEnlarged() {
        let screen = CGSize(width: 1512, height: 982)
        #expect(PageSize.open(base: CGSize(width: 320, height: 138), sheetHeight: nil, size: .large, screen: screen)
            == CGSize(width: 400, height: 173))
        #expect(PageSize.open(base: nil, sheetHeight: nil, size: .large, screen: screen) == CGSize(width: 800, height: 250))
    }

    @Test func aTallerSheetGrowsDownButNotPastMostOfTheScreen() {
        let screen = CGSize(width: 1512, height: 982)
        let base = CGSize(width: 544, height: 240)
        #expect(PageSize.open(base: base, sheetHeight: 300, size: .large, screen: screen).height == 375)
        #expect(PageSize.open(base: base, sheetHeight: 100, size: .large, screen: screen).height == 300)
        #expect(PageSize.open(base: base, sheetHeight: 5_000, size: .large, screen: screen).height == 786)
    }

    @Test func aPageIsNeverWiderThanTheScreenLeavesRoomFor() {
        let narrow = CGSize(width: 900, height: 700)
        let size = PageSize.open(base: CGSize(width: 800, height: 200), sheetHeight: nil, size: .extraLarge, screen: narrow)
        #expect(size.width <= 900 - 2 * OrbitLayout.gutter * NotchSize.extraLarge.scale)
    }

    @Test func wingsAreAsWideAsTheirContentWithinBounds() {
        #expect(ActivityWings.width(content: 10) == ActivityWings.narrowest)
        #expect(ActivityWings.width(content: 40) == 52)
        #expect(ActivityWings.width(content: 200) == ActivityWings.widest)
        #expect(ActivityWings.width(content: 200, combined: true) == ActivityWings.widestCombined)
    }

    @Test func theChosenRestingThingShowsWhileItIsTrue() {
        let all = ["media": 0, "timer": 1, "agent": 2]
        #expect(RestingSelection().shown(all) == .one("agent"))
        #expect(RestingSelection(preferred: .one("media")).shown(all) == .one("media"))
        #expect(RestingSelection(preferred: .one("notes")).shown(all) == .one("agent"))
    }

    @Test func aPairShowsWhileBothAreTrueAndOneOfItOtherwise() {
        let pair = RestingSelection(preferred: .pair(primary: "media", companion: "timer"))
        #expect(pair.shown(["media": 0, "timer": 1]) == .pair(primary: "media", companion: "timer"))
        #expect(pair.shown(["timer": 1, "agent": 2]) == .one("timer"))
        #expect(pair.shown([:]) == nil)
    }

    @Test func theChoiceIsKeptAsText() {
        for choice in [RestingSelection.Choice.one("media"), .pair(primary: "media", companion: "timer")] {
            let selection = RestingSelection(preferred: choice)
            #expect(RestingSelection(stored: selection.stored) == selection)
        }
        #expect(RestingSelection(stored: nil).preferred == nil)
    }

    @Test func eachPageGetsAFreeLetterOfItsName() {
        let letters = ExploreKeys.letters(for: ["Clipboard", "Calendar", "Đang phát", "Ghi chú", "Công cụ"])
        #expect(letters == ["C", "A", "D", "G", "O"])
        #expect(ExploreKeys.letters(for: ["Aa", "A", "a"]) == ["A", nil, nil])
    }

    @Test func theMaterialIsKeptAndGlassIsTheStandard() {
        let store = ShellSettingsStore(defaults: InMemoryDefaults())
        #expect(store.material == .glass)
        store.material = .black
        #expect(store.material == .black)
    }

    @Test func theWindowLeavesRoomForTheButtonsAndTheOvershoot() {
        let margin = OrbitLayout.standard.windowMargin(scale: 1)
        #expect(margin.width == OrbitLayout.gutter + NotchMotion.overshootRoom)
        #expect(margin.height == OrbitLayout.gutter + NotchMotion.overshootRoom)
        let noBottom = OrbitLayout(stored: ["left0=explore"]).windowMargin(scale: 1)
        #expect(noBottom.height == NotchMotion.overshootRoom)
        #expect(OrbitLayout(stored: []).windowMargin(scale: 1).width == NotchMotion.overshootRoom)
    }

    @Test func theButtonsAreWithinReachOfThePointer() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, auxLeftWidth: 662, auxRightWidth: 662,
            menuBarHeight: 32)
        let geometry = NotchGeometry(screen: screen)
        let size = CGSize(width: 400, height: 172)
        let reach = OrbitLayout.standard.reach(scale: 1)
        let rect = geometry.openHitRect(size: size, reach: reach)
        let open = geometry.openRect(size: size)
        #expect(rect.minX == open.minX - reach.width)
        #expect(rect.maxX == open.maxX + reach.width)
        #expect(rect.minY == open.minY - reach.height)
        let window = geometry.openWindowRect(size: size, margin: CGSize(width: 70, height: 70))
        #expect(window.width == size.width + 140)
        #expect(window.maxY == open.maxY)
        #expect(window.midX == open.midX)
    }

    @Test func onlyQuietNewsBecomesOneLine() {
        #expect(NoticeForm.choose(warns: false, hasTitle: false, rows: 1, offersAction: false) == .line)
        #expect(NoticeForm.choose(warns: true, hasTitle: false, rows: 1, offersAction: false) == .sign)
        #expect(NoticeForm.choose(warns: false, hasTitle: true, rows: 0, offersAction: false) == .sign)
        #expect(NoticeForm.choose(warns: false, hasTitle: false, rows: 2, offersAction: false) == .sign)
        #expect(NoticeForm.choose(warns: false, hasTitle: false, rows: 1, offersAction: true) == .sign)
    }
}
