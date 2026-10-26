import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct DisplayChooserTests {
    private func display(notch: Bool = false, main: Bool = false, pointer: Bool = false) -> DisplayChooser.Candidate {
        DisplayChooser.Candidate(hasNotch: notch, isMain: main, containsPointer: pointer)
    }

    @Test func automaticPrefersTheDisplayWithANotch() {
        let displays = [display(main: true, pointer: true), display(notch: true)]
        #expect(DisplayChooser.choose(.automatic, among: displays) == 1)
    }

    @Test func automaticFallsBackToTheMainDisplay() {
        let displays = [display(), display(main: true)]
        #expect(DisplayChooser.choose(.automatic, among: displays) == 1)
    }

    @Test func mainFollowsTheDisplayWithTheActiveWindow() {
        let displays = [display(notch: true), display(main: true)]
        #expect(DisplayChooser.choose(.main, among: displays) == 1)
    }

    @Test func pointerFollowsThePointerAndFallsBackToAutomatic() {
        let displays = [display(notch: true), display(main: true), display(pointer: true)]
        #expect(DisplayChooser.choose(.pointer, among: displays) == 2)
        #expect(DisplayChooser.choose(.pointer, among: [display(main: true), display(notch: true)]) == 1)
    }

    @Test func withNothingMarkedTheFirstDisplayIsUsed() {
        #expect(DisplayChooser.choose(.main, among: [display(), display()]) == 0)
        #expect(DisplayChooser.choose(.automatic, among: [display()]) == 0)
    }

    @Test func noDisplaysMeansNoChoice() {
        for mode in DisplayMode.allCases {
            #expect(DisplayChooser.choose(mode, among: []) == nil)
        }
    }

    @Test func onEveryDisplayTheNotchThatAnswersIsTheOneUnderThePointer() {
        let displays = [display(notch: true), display(main: true), display(pointer: true)]
        #expect(DisplayChooser.choose(.all, among: displays) == 2)
        // With the pointer nowhere to be found, the display the notch would otherwise be on.
        #expect(DisplayChooser.choose(.all, among: [display(main: true), display(notch: true)]) == 1)
    }

    @Test func onEveryDisplayAllTheOthersShowTheNotchToo() {
        let displays = [display(notch: true), display(main: true), display(pointer: true)]
        #expect(DisplayChooser.others(.all, among: displays) == [0, 1])
        #expect(DisplayChooser.others(.all, among: [display(notch: true, main: true, pointer: true)]) == [])
        #expect(DisplayChooser.others(.all, among: []) == [])
    }

    @Test func aPointerOnTheTopEdgeOfADisplayIsOnThatDisplay() {
        // Pointer positions are measured from the bottom: on the top row of a display 1440
        // high that starts at 114, the pointer is at exactly 1554, the display's upper bound.
        let external = CGRect(x: 1512, y: 114, width: 2560, height: 1440)
        #expect(DisplayChooser.display(external, holds: CGPoint(x: 2792, y: 1554)))
        #expect(DisplayChooser.display(external, holds: CGPoint(x: 2792, y: 800)))
        #expect(DisplayChooser.display(external, holds: CGPoint(x: 1512, y: 115)))
    }

    @Test func aPointerOnTheLineBetweenTwoDisplaysIsOnOnlyOneOfThem() {
        // The line where one display ends and the next begins is the top row of the lower
        // one and the first column of the one to the right.
        let lower = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let upper = CGRect(x: 0, y: 982, width: 1512, height: 982)
        let right = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let onTheRow = CGPoint(x: 700, y: 982)
        #expect(DisplayChooser.display(lower, holds: onTheRow))
        #expect(!DisplayChooser.display(upper, holds: onTheRow))
        let onTheColumn = CGPoint(x: 1512, y: 500)
        #expect(!DisplayChooser.display(lower, holds: onTheColumn))
        #expect(DisplayChooser.display(right, holds: onTheColumn))
    }

    @Test func withThePointerNowhereTheNotchStaysOnTheDisplayItIsOn() {
        // Rather than jumping to the display with a hardware notch and back.
        let displays = [display(notch: true), display(main: true)]
        #expect(DisplayChooser.choose(.all, among: displays, current: 1) == 1)
        #expect(DisplayChooser.choose(.pointer, among: displays, current: 1) == 1)
        // A display that is gone is not stayed on.
        #expect(DisplayChooser.choose(.all, among: displays, current: 5) == 0)
        // The other modes do not follow the pointer and do not stay either.
        #expect(DisplayChooser.choose(.automatic, among: displays, current: 1) == 0)
        #expect(DisplayChooser.others(.all, among: displays, current: 1) == [0])
    }

    @Test func onOneDisplayNoOtherShowsTheNotch() {
        let displays = [display(notch: true), display(main: true), display(pointer: true)]
        for mode in [DisplayMode.automatic, .main, .pointer] {
            #expect(DisplayChooser.others(mode, among: displays) == [])
        }
    }

    @Test func theNotchGoesToThePointersDisplayOnlyWhenItFollowsThePointer() {
        #expect(DisplayMode.allCases.filter(\.followsPointer) == [.all, .pointer])
    }

    @Test func theModeIsRememberedAndDefaultsToEveryDisplay() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        #expect(store.displayMode == .all)
        store.displayMode = .pointer
        #expect(ShellSettingsStore(defaults: defaults).displayMode == .pointer)
        defaults.set("everywhere", forKey: ShellSettingsStore.Key.displayMode)
        #expect(store.displayMode == .all)
    }
}
