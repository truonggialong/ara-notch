import CoreGraphics
import Foundation
import Testing
@testable import TranslateCore

@Suite struct SelectionGestureTests {
    @Test func aDragMaySelect() {
        #expect(SelectionGesture.maySelect(down: CGPoint(x: 10, y: 10), up: CGPoint(x: 60, y: 12), clickCount: 1))
    }

    @Test func aPlainClickDoesNot() {
        #expect(!SelectionGesture.maySelect(down: CGPoint(x: 10, y: 10), up: CGPoint(x: 11, y: 12), clickCount: 1))
    }

    @Test func aDoubleOrTripleClickMaySelect() {
        let point = CGPoint(x: 10, y: 10)
        #expect(SelectionGesture.maySelect(down: point, up: point, clickCount: 2))
        #expect(SelectionGesture.maySelect(down: point, up: point, clickCount: 3))
    }
}

@Suite struct SmartSelectionTests {
    @Test func trimsTheSelection() {
        #expect(SmartSelection("  xin chào \n")?.text == "xin chào")
    }

    @Test func nothingOrOnlySpaceIsNoSelection() {
        #expect(SmartSelection(nil) == nil)
        #expect(SmartSelection("") == nil)
        #expect(SmartSelection(" \n\t ") == nil)
    }

    @Test func aVeryLongSelectionGetsNoBar() {
        #expect(SmartSelection(String(repeating: "a", count: SmartSelection.maxLength)) != nil)
        #expect(SmartSelection(String(repeating: "a", count: SmartSelection.maxLength + 1)) == nil)
    }

    @Test func plainTextOffersCopyTranslateAndSearch() {
        #expect(SmartSelection("con cáo nâu")?.actions == [.copy, .translate, .search])
    }

    @Test func aLinkAlsoOffersToOpenIt() throws {
        let selection = try #require(SmartSelection("https://example.com/a?b=1"))
        #expect(selection.link?.absoluteString == "https://example.com/a?b=1")
        #expect(selection.actions == [.copy, .openLink])
    }

    @Test func textThatOnlyContainsALinkIsNotALink() {
        #expect(SmartSelection("xem https://example.com nhé")?.link == nil)
        #expect(SmartSelection("ftp://example.com/file")?.link == nil)
        #expect(SmartSelection("example")?.link == nil)
    }

    @Test func longTextIsNotOfferedForSearch() {
        let long = String(repeating: "chữ ", count: 100)
        #expect(SmartSelection(long)?.actions == [.copy, .translate])
    }

    @Test func theSearchAddressCarriesTheTextEncoded() throws {
        let url = try #require(SmartSelection("cà phê & trà")?.searchURL)
        #expect(url.absoluteString == "https://www.google.com/search?q=c%C3%A0%20ph%C3%AA%20%26%20tr%C3%A0")
    }
}

@Suite struct SelectionTrackerTests {
    private let hello = SmartSelection("hello")
    private let world = SmartSelection("world")

    @Test func aNewSelectionIsShown() {
        var tracker = SelectionTracker()
        let shown1 = tracker.shouldShow(hello, pid: 1)
        #expect(shown1)
    }

    @Test func theSameSelectionIsNotShownTwiceInARow() {
        var tracker = SelectionTracker()
        let shown2 = tracker.shouldShow(hello, pid: 1)
        #expect(shown2)
        // A later drag, of a window say, finds the same text still selected.
        let shown3 = tracker.shouldShow(hello, pid: 1)
        #expect(!shown3)
        let shown4 = tracker.shouldShow(world, pid: 1)
        #expect(shown4)
    }

    @Test func theSameTextInAnotherAppIsANewSelection() {
        var tracker = SelectionTracker()
        let shown5 = tracker.shouldShow(hello, pid: 1)
        #expect(shown5)
        let shown6 = tracker.shouldShow(hello, pid: 2)
        #expect(shown6)
    }

    @Test func noSelectionShowsNothingAndForgetsTheLastOne() {
        var tracker = SelectionTracker()
        let shown7 = tracker.shouldShow(hello, pid: 1)
        #expect(shown7)
        let shown8 = tracker.shouldShow(nil, pid: 1)
        #expect(!shown8)
        let shown9 = tracker.shouldShow(hello, pid: 1)
        #expect(shown9)
    }

    @Test func aPlainClickForgetsTheLastSelection() {
        var tracker = SelectionTracker()
        let shown10 = tracker.shouldShow(hello, pid: 1)
        #expect(shown10)
        tracker.reset()
        let shown11 = tracker.shouldShow(hello, pid: 1)
        #expect(shown11)
    }
}

@Suite struct SmartSelectionSettingsTests {
    @Test func smartSelectionIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = TranslateSettingsStore(defaults: defaults)
        #expect(store.smartSelection == false)
        store.smartSelection = true
        #expect(TranslateSettingsStore(defaults: defaults).smartSelection == true)
    }
}
