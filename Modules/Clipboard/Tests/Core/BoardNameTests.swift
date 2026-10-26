import Testing
@testable import ClipboardCore

@Suite struct BoardNameTests {
    @Test func aNewBoardIsOfferedTheFirstNumberedNameNotInUse() {
        #expect(BoardNames.suggested(base: "Board", existing: []) == "Board 1")
        #expect(BoardNames.suggested(base: "Board", existing: ["Board 1", "Work", "board 2"]) == "Board 3")
    }

    @Test func aGapInTheNumbersIsFilled() {
        #expect(BoardNames.suggested(base: "Bảng", existing: ["Bảng 1", "Bảng 3"]) == "Bảng 2")
    }
}
