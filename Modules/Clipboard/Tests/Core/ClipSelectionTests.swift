import Testing
@testable import ClipboardCore

@Suite struct ClipSelectionTests {
    private let ids: [Int64] = [10, 20, 30]

    private func selection(at id: Int64) -> ClipSelection {
        var selection = ClipSelection()
        selection.select(id: id, in: ids)
        return selection
    }

    @Test func startsEmpty() {
        let selection = ClipSelection()
        #expect(selection.selectedID == nil)
        #expect(selection.index(in: ids) == nil)
    }

    @Test func syncSelectsFirstWhenNothingSelected() {
        var selection = ClipSelection()
        selection.sync(with: ids)
        #expect(selection.selectedID == 10)
    }

    @Test func syncKeepsExistingSelection() {
        var selection = selection(at: 20)
        selection.sync(with: [30, 20, 10])
        #expect(selection.selectedID == 20)
        #expect(selection.index(in: [30, 20, 10]) == 1)
    }

    @Test func syncFallsBackToFirstWhenSelectionDisappears() {
        var selection = selection(at: 20)
        selection.sync(with: [10, 30])
        #expect(selection.selectedID == 10)
    }

    @Test func syncWithEmptyListClearsSelection() {
        var selection = selection(at: 20)
        selection.sync(with: [])
        #expect(selection.selectedID == nil)
    }

    @Test func moveNextAdvancesAndStopsAtEnd() {
        var selection = selection(at: 10)
        selection.moveNext(in: ids)
        #expect(selection.selectedID == 20)
        selection.moveNext(in: ids)
        #expect(selection.selectedID == 30)
        selection.moveNext(in: ids)
        #expect(selection.selectedID == 30)
    }

    @Test func movePreviousStopsAtStart() {
        var selection = selection(at: 20)
        selection.movePrevious(in: ids)
        #expect(selection.selectedID == 10)
        selection.movePrevious(in: ids)
        #expect(selection.selectedID == 10)
    }

    @Test func movingWithNoSelectionSelectsFirst() {
        var forward = ClipSelection()
        forward.moveNext(in: ids)
        #expect(forward.selectedID == 10)

        var backward = ClipSelection()
        backward.movePrevious(in: ids)
        #expect(backward.selectedID == 10)
    }

    @Test func movingWhenSelectionIsGoneSelectsFirst() {
        var selection = selection(at: 20)
        selection.moveNext(in: [10, 30])
        #expect(selection.selectedID == 10)
    }

    @Test func movingInEmptyListDoesNothing() {
        var selection = ClipSelection()
        selection.moveNext(in: [])
        selection.movePrevious(in: [])
        #expect(selection.selectedID == nil)
    }

    @Test func selectIndexInRange() {
        var selection = ClipSelection()
        let didSelect = selection.select(index: 2, in: ids)
        #expect(didSelect)
        #expect(selection.selectedID == 30)
    }

    @Test(arguments: [3, -1, 99])
    func selectIndexOutOfRangeIsIgnored(_ index: Int) {
        var selection = selection(at: 20)
        let didSelect = selection.select(index: index, in: ids)
        #expect(!didSelect)
        #expect(selection.selectedID == 20)
    }

    @Test func selectIDIgnoresUnknownID() {
        var selection = selection(at: 20)
        selection.select(id: 99, in: ids)
        #expect(selection.selectedID == 20)
    }
}
