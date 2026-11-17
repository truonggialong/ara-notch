import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct ScrollLayoutTests {
    @Test func onlyTheEndsWithMoreBeyondThemFade() {
        #expect(ScrollEdges.of(offset: 0, visible: 100, content: 300) == ScrollEdges(start: false, end: true))
        #expect(ScrollEdges.of(offset: 120, visible: 100, content: 300) == ScrollEdges(start: true, end: true))
        #expect(ScrollEdges.of(offset: 200, visible: 100, content: 300) == ScrollEdges(start: true, end: false))
        #expect(ScrollEdges.of(offset: 0, visible: 100, content: 80) == ScrollEdges(start: false, end: false))
    }

    @Test func itemsThatFitAreLaidInRowsAcrossTheWidth() {
        let plan = RailLayout.plan(count: 8, item: CGSize(width: 100, height: 60), spacing: 8, area: CGSize(width: 440, height: 140))
        #expect(plan == RailLayout.Plan(rows: 2, columns: 4, scrolls: false))
        let five = RailLayout.plan(count: 5, item: CGSize(width: 100, height: 60), spacing: 8, area: CGSize(width: 440, height: 140))
        #expect(five == RailLayout.Plan(rows: 2, columns: 4, scrolls: false))
    }

    @Test func aShortAreaFillsColumnsAndScrollsSideways() {
        let plan = RailLayout.plan(count: 8, item: CGSize(width: 100, height: 60), spacing: 8, area: CGSize(width: 300, height: 70))
        #expect(plan == RailLayout.Plan(rows: 1, columns: 8, scrolls: true))
        let two = RailLayout.plan(count: 9, item: CGSize(width: 100, height: 60), spacing: 8, area: CGSize(width: 300, height: 140))
        #expect(two == RailLayout.Plan(rows: 2, columns: 5, scrolls: true))
        #expect(RailLayout.plan(count: 0, item: .zero, spacing: 8, area: .zero).columns == 0)
    }

    @Test func aNoticeActsOnlyIfItIsStillTheOnePressed() {
        #expect(NoticeClick.acts(pressedID: "a", shownID: "a", releasedInside: true))
        #expect(!NoticeClick.acts(pressedID: "a", shownID: "b", releasedInside: true))
        #expect(!NoticeClick.acts(pressedID: "a", shownID: nil, releasedInside: true))
        #expect(!NoticeClick.acts(pressedID: "a", shownID: "a", releasedInside: false))
    }

    @Test func aSliderReachesBothEndsNearItsEdges() {
        #expect(SliderValue.fraction(at: 3, width: 100, endZone: 6) == 0)
        #expect(SliderValue.fraction(at: 97, width: 100, endZone: 6) == 1)
        #expect(SliderValue.fraction(at: 50, width: 100, endZone: 6) == 0.5)
        #expect(SliderValue.fraction(at: 5, width: 10, endZone: 6) == 0.5)
    }

    @Test func theWheelMovesASliderByATwentiethAndSidewaysSwipesLeaveIt() {
        #expect(SliderValue.wheelStep(deltaX: 0, deltaY: 1, isPrecise: false, isInverted: false) == 0.05)
        #expect(SliderValue.wheelStep(deltaX: 0, deltaY: 3, isPrecise: false, isInverted: true) == -0.05)
        #expect(SliderValue.wheelStep(deltaX: 8, deltaY: 2, isPrecise: true, isInverted: false) == nil)
        #expect(SliderValue.wheelStep(deltaX: 0, deltaY: 0, isPrecise: true, isInverted: false) == nil)
        #expect(SliderValue.wheelStep(deltaX: 0, deltaY: 500, isPrecise: true, isInverted: false) == 0.1)
    }
}
