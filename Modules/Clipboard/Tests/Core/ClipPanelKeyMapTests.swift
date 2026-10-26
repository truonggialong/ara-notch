import Testing
@testable import ClipboardCore

private enum Key {
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    static let returnKey: UInt16 = 36, enter: UInt16 = 76, escape: UInt16 = 53, delete: UInt16 = 51
    static let a: UInt16 = 0, zero: UInt16 = 29
    static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
}

private func command(
    _ keyCode: UInt16, _ modifiers: KeyModifiers = [],
    axis: ClipListAxis = .vertical, searchIsEmpty: Bool = true
) -> ClipPanelCommand {
    ClipPanelKeyMap.command(keyCode: keyCode, modifiers: modifiers, axis: axis, searchIsEmpty: searchIsEmpty)
}

@Suite struct ClipPanelKeyMapArrowTests {
    @Test func verticalListUsesUpAndDown() {
        #expect(command(Key.down) == .moveNext)
        #expect(command(Key.up) == .movePrevious)
        #expect(command(Key.left) == .passThrough)
        #expect(command(Key.right) == .passThrough)
    }

    @Test func horizontalListUsesLeftAndRightWhileSearchIsEmpty() {
        #expect(command(Key.right, axis: .horizontal) == .moveNext)
        #expect(command(Key.left, axis: .horizontal) == .movePrevious)
        #expect(command(Key.up, axis: .horizontal) == .passThrough)
        #expect(command(Key.down, axis: .horizontal) == .passThrough)
    }

    @Test func horizontalArrowsMoveTheCaretOnceTextIsTyped() {
        #expect(command(Key.right, axis: .horizontal, searchIsEmpty: false) == .passThrough)
        #expect(command(Key.left, axis: .horizontal, searchIsEmpty: false) == .passThrough)
    }

    @Test func verticalArrowsStillNavigateWhileTyping() {
        #expect(command(Key.down, searchIsEmpty: false) == .moveNext)
    }

    @Test(arguments: [KeyModifiers.option, .shift, .command, .control])
    func arrowsWithModifiersAreLeftToTheTextField(_ modifier: KeyModifiers) {
        #expect(command(Key.down, modifier) == .passThrough)
        #expect(command(Key.right, modifier, axis: .horizontal) == .passThrough)
    }
}

@Suite struct ClipPanelKeyMapActionTests {
    @Test func returnPastes() {
        #expect(command(Key.returnKey) == .paste)
        #expect(command(Key.enter) == .paste)
    }

    @Test func commandReturnCopies() {
        #expect(command(Key.returnKey, .command) == .copy)
    }

    @Test func shiftReturnIsPassedThrough() {
        #expect(command(Key.returnKey, .shift) == .passThrough)
    }

    @Test func commandDeleteDeletes() {
        #expect(command(Key.delete, .command) == .delete)
        #expect(command(Key.delete) == .passThrough)
    }

    @Test func commandDigitPastesThatPosition() {
        for (index, keyCode) in Key.digits.enumerated() {
            #expect(command(keyCode, .command) == .pasteIndex(index))
        }
    }

    @Test func digitsNeedExactlyCommand() {
        #expect(command(Key.digits[0]) == .passThrough)
        #expect(command(Key.digits[0], [.command, .shift]) == .passThrough)
        #expect(command(Key.zero, .command) == .passThrough)
    }

    @Test func escapeClearsSearchBeforeClosing() {
        #expect(command(Key.escape, searchIsEmpty: false) == .clearSearch)
        #expect(command(Key.escape, searchIsEmpty: true) == .close)
    }

    @Test func ordinaryTypingIsPassedThrough() {
        #expect(command(Key.a) == .passThrough)
        #expect(command(Key.a, .command) == .passThrough)
    }
}

@Suite struct ClipPanelKeyMapUndoAndPreviewTests {
    @Test func commandZTakesBackADeletion() {
        #expect(command(6, .command) == .undo)
        #expect(command(6) == .passThrough)
        #expect(command(6, [.command, .shift]) == .passThrough)
    }

    @Test func spaceShowsTheChosenClipWhileNothingIsTyped() {
        #expect(command(49) == .preview)
        #expect(command(49, axis: .horizontal) == .preview)
    }

    @Test func spaceIsALetterOnceTextIsTyped() {
        #expect(command(49, searchIsEmpty: false) == .passThrough)
    }
}
