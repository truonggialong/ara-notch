import ClipboardCore
import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct ChipRowTests {
    @Test func theChosenBoardIsTheChipToBringIntoView() {
        #expect(BoardChipsView.chosenChip(boardID: 5, search: "", savedFilters: []) == "board:5")
    }

    @Test func aKindFilterInTheSearchIsTheChipToBringIntoView() {
        #expect(BoardChipsView.chosenChip(boardID: nil, search: "@color", savedFilters: []) == "kind:color")
    }

    @Test func aSavedSearchBeingShownIsTheChipToBringIntoView() {
        #expect(BoardChipsView.chosenChip(boardID: nil, search: "hoá đơn", savedFilters: ["hoá đơn"]) == "filter:hoá đơn")
    }

    @Test func withNothingChosenTheAllChipIsBroughtIntoView() {
        #expect(BoardChipsView.chosenChip(boardID: nil, search: "xin chào", savedFilters: []) == "all")
    }
}
