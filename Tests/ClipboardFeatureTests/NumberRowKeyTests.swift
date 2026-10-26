import Testing
@testable import ClipboardFeature

@Suite struct NumberRowKeyTests {
    /// The modifiers chosen before the rows moved to the clipboard are read from the same keys.
    @Test func theNumberRowsKeepTheirStoredKeys() {
        #expect(ClipboardNumberRows.pinned.storageKey == "shortcut.quickPasteModifiers")
        #expect(ClipboardNumberRows.recent.storageKey == "shortcut.recentPasteModifiers")
    }

    @Test func theRowsAreNamedForWhatTheyPaste() {
        #expect(ClipboardNumberRows.pinned.titleKey == "settings.shortcuts.quickPaste")
        #expect(ClipboardNumberRows.recent.titleKey == "settings.shortcuts.recentPaste")
        #expect(ClipboardNumberRows.all == [ClipboardNumberRows.recent, ClipboardNumberRows.pinned])
    }
}
