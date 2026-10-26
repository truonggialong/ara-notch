import Testing
@testable import ClipboardCore

@Suite struct ClipMultiSelectionTests {
    private let order: [Int64] = [10, 20, 30, 40, 50]

    @Test func aPlainClickSelectsOnlyThatClip() {
        var selection = ClipMultiSelection()
        selection.click(20, in: order)
        selection.click(40, in: order)
        #expect(selection.ids == [40])
        #expect(selection.primary == 40)
    }

    @Test func commandClickAddsAndRemoves() {
        var selection = ClipMultiSelection()
        selection.click(20, in: order)
        selection.click(40, in: order, toggling: true)
        #expect(selection.ids == [20, 40])
        #expect(selection.primary == 40)
        selection.click(20, in: order, toggling: true)
        #expect(selection.ids == [40])
        #expect(selection.primary == 40)
        selection.click(40, in: order, toggling: true)
        #expect(selection.ids.isEmpty)
        #expect(selection.primary == nil)
    }

    @Test func shiftClickSelectsTheRangeFromTheLastPlainClick() {
        var selection = ClipMultiSelection()
        selection.click(40, in: order)
        selection.click(20, in: order, extending: true)
        #expect(selection.ids == [20, 30, 40])
        // The range pivots on the same anchor.
        selection.click(50, in: order, extending: true)
        #expect(selection.ids == [40, 50])
    }

    @Test func shiftClickWithNothingSelectedStartsFromTheTop() {
        var selection = ClipMultiSelection()
        selection.click(30, in: order, extending: true)
        #expect(selection.ids == [10, 20, 30])
    }

    @Test func orderedFollowsTheListNotTheClicks() {
        var selection = ClipMultiSelection()
        selection.click(50, in: order)
        selection.click(10, in: order, toggling: true)
        selection.click(30, in: order, toggling: true)
        #expect(selection.ordered(in: order) == [10, 30, 50])
    }

    @Test func clipsThatLeftTheListAreDropped() {
        var selection = ClipMultiSelection()
        selection.click(20, in: order)
        selection.click(40, in: order, toggling: true)
        selection.sync(with: [10, 20, 30])
        #expect(selection.ids == [20])
        #expect(selection.primary == 20)
        selection.sync(with: [])
        #expect(selection.ids.isEmpty)
        #expect(selection.primary == nil)
    }

    @Test func aClickOnAnUnlistedClipIsIgnored() {
        var selection = ClipMultiSelection()
        selection.click(20, in: order)
        selection.click(99, in: order)
        #expect(selection.ids == [20])
    }

    @Test func dragCarriesTheWholeSelectionOnlyWhenTheDraggedClipIsInIt() {
        var selection = ClipMultiSelection()
        selection.click(20, in: order)
        selection.click(40, in: order, toggling: true)
        #expect(selection.dragged(from: 40, in: order) == [20, 40])
        #expect(selection.dragged(from: 50, in: order) == [50])
    }

    @Test func clipIdentityListsRoundTrip() {
        #expect(ClipMultiSelection.encode([3, 1, 2]) == "3,1,2")
        #expect(ClipMultiSelection.decode("3,1,2") == [3, 1, 2])
        #expect(ClipMultiSelection.decode("7") == [7])
        #expect(ClipMultiSelection.decode("1, x,,2 ") == [1, 2])
        #expect(ClipMultiSelection.decode("").isEmpty)
    }
}
