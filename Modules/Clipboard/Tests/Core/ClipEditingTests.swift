import Foundation
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func withStore(_ body: (ClipboardStore, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-edit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(try ClipboardStore(directory: directory, inMemory: true, maxItems: 500), directory)
}

private let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")

@Suite struct ClipTitleTests {
    @Test func aClipCanBeGivenATitle() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("0912 345 678"), source: notes, at: date(1)))
            #expect(item.title == nil)
            try store.setTitle(id: item.id, title: "  Số của anh Minh ")
            #expect(try store.item(id: item.id)?.title == "Số của anh Minh")
        }
    }

    @Test func anEmptyTitleRemovesIt() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("abc"), source: notes, at: date(1)))
            try store.setTitle(id: item.id, title: "Tên")
            try store.setTitle(id: item.id, title: "   ")
            #expect(try store.item(id: item.id)?.title == nil)
        }
    }

    @Test func copyingTheSameContentAgainKeepsTheTitle() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("abc"), source: notes, at: date(1)))
            try store.setTitle(id: item.id, title: "Tên")
            let again = try #require(try store.add(.text("abc"), source: notes, at: date(2)))
            #expect(again.id == item.id)
            #expect(again.title == "Tên")
        }
    }

    @Test func searchFindsAClipByItsTitle() {
        var item = makeItem(text: "0912 345 678")
        item.title = "Số của anh Minh"
        #expect(ClipQuery("anh minh").matches(item))
        #expect(ClipQuery("0912").matches(item))
        #expect(!ClipQuery("chị lan").matches(item))
    }
}

@Suite struct ClipTextEditingTests {
    @Test func theTextOfAClipCanBeChanged() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("xin chao"), source: notes, at: date(1)))
            let result = try store.updateText(id: item.id, text: "xin chào", at: date(5))
            #expect(result == .updated)
            let edited = try #require(try store.item(id: item.id))
            #expect(edited.text == "xin chào")
            #expect(edited.byteSize == "xin chào".utf8.count)
            // An edit is a use: the clip moves to the top. Its creation date stays.
            #expect(edited.lastUsedAt == date(5))
            #expect(edited.createdAt == date(1))
        }
    }

    @Test func theKindFollowsTheNewText() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("ghi chú"), source: notes, at: date(1)))
            _ = try store.updateText(id: item.id, text: "https://example.com/a", at: date(2))
            #expect(try store.item(id: item.id)?.kind == .link)
        }
    }

    @Test func formattingThatNoLongerMatchesIsDropped() throws {
        try withStore { store, directory in
            let rich = ClipRichData(rtf: Data("{\\rtf1 cu}".utf8), html: Data("<b>cu</b>".utf8))
            let item = try #require(try store.add(.text("cu"), rich: rich, source: notes, at: date(1)))
            #expect(item.hasRichData)
            _ = try store.updateText(id: item.id, text: "mới", at: date(2))
            let edited = try #require(try store.item(id: item.id))
            #expect(!edited.hasRichData)
            #expect(store.richData(for: edited) == nil)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("blobs").path)) ?? []
            #expect(files.isEmpty)
        }
    }

    @Test func aLinkPreviewOfTheOldLinkIsDropped() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("https://example.com/a"), source: notes, at: date(1)))
            try store.setLinkPreview(id: item.id, title: "Trang A", imageData: nil, at: date(2))
            _ = try store.updateText(id: item.id, text: "https://example.com/b", at: date(3))
            let edited = try #require(try store.item(id: item.id))
            #expect(edited.linkTitle == nil)
            #expect(edited.linkCheckedAt == nil)
        }
    }

    @Test func textThatAnotherClipAlreadyHasIsRefused() throws {
        try withStore { store, _ in
            try store.add(.text("một"), source: notes, at: date(1))
            let item = try #require(try store.add(.text("hai"), source: notes, at: date(2)))
            let result = try store.updateText(id: item.id, text: "một", at: date(3))
            #expect(result == .duplicate)
            #expect(try store.item(id: item.id)?.text == "hai")
        }
    }

    @Test func emptyTextIsRefused() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("hai"), source: notes, at: date(2)))
            let result = try store.updateText(id: item.id, text: "  \n ", at: date(3))
            #expect(result == .notEditable)
            #expect(try store.item(id: item.id)?.text == "hai")
        }
    }

    @Test func imagesAndFilesCannotBeEditedAsText() throws {
        try withStore { store, _ in
            let image = try #require(try store.add(.image(Data([0x89, 0x50, 1, 2])), source: notes, at: date(1)))
            let file = try #require(try store.add(.files(["/tmp/a.txt"]), source: notes, at: date(2)))
            #expect(try store.updateText(id: image.id, text: "x", at: date(3)) == .notEditable)
            #expect(try store.updateText(id: file.id, text: "x", at: date(3)) == .notEditable)
        }
    }

    @Test func savingTheSameTextChangesNothing() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("hai"), source: notes, at: date(2)))
            #expect(try store.updateText(id: item.id, text: "hai", at: date(9)) == .unchanged)
            #expect(try store.item(id: item.id)?.lastUsedAt == date(2))
        }
    }

    @Test func theTitleSurvivesAnEdit() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("hai"), source: notes, at: date(2)))
            try store.setTitle(id: item.id, title: "Tên")
            _ = try store.updateText(id: item.id, text: "ba", at: date(3))
            #expect(try store.item(id: item.id)?.title == "Tên")
        }
    }
}

@Suite struct ClipRecognizedTextTests {
    @Test func textReadFromAnImageIsKeptWithIt() throws {
        try withStore { store, _ in
            let image = try #require(try store.add(.image(Data([0x89, 0x50, 1, 2])), source: notes, at: date(1)))
            #expect(image.recognizedText == nil)
            try store.setRecognizedText(id: image.id, text: "Hoá đơn tháng 10")
            #expect(try store.item(id: image.id)?.recognizedText == "Hoá đơn tháng 10")
        }
    }

    @Test func anImageWithNoTextIsMarkedAsReadToo() throws {
        try withStore { store, _ in
            let image = try #require(try store.add(.image(Data([0x89, 0x50, 1, 2])), source: notes, at: date(1)))
            #expect(try store.imagesAwaitingRecognition(limit: 10).map(\.id) == [image.id])
            try store.setRecognizedText(id: image.id, text: "")
            // Empty, not nil: read, and nothing found. It is not read again.
            #expect(try store.item(id: image.id)?.recognizedText == "")
            #expect(try store.imagesAwaitingRecognition(limit: 10).isEmpty)
        }
    }

    @Test func searchFindsAnImageByTheTextInIt() {
        var item = makeItem(kind: .image, text: "")
        item.recognizedText = "Hoá đơn tháng 10"
        #expect(ClipQuery("hoa don").matches(item))
        #expect(!ClipQuery("biên lai").matches(item))
    }
}

@Suite struct ClipSchemaUpgradeTests {
    @Test func aStoreFromBeforeTitlesIsUpgraded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-upgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try ClipboardStore(directory: directory)
            try store.add(.text("cũ"), source: notes, at: date(1))
            // Put the store back to how version 5 left it.
            try store.database.execute("ALTER TABLE items DROP COLUMN title")
            try store.database.execute("ALTER TABLE items DROP COLUMN ocr_text")
            try store.database.setUserVersion(5)
        }
        let upgraded = try ClipboardStore(directory: directory)
        let item = try #require(try upgraded.items().first)
        #expect(item.text == "cũ")
        try upgraded.setTitle(id: item.id, title: "Tên")
        #expect(try upgraded.item(id: item.id)?.title == "Tên")
    }
}

@Suite struct PlainPasteKeyTests {
    @Test func optionReturnPastesWithoutFormatting() {
        let command = ClipPanelKeyMap.command(
            keyCode: 36, modifiers: .option, axis: .vertical, searchIsEmpty: true)
        #expect(command == .pastePlain)
    }

    @Test func plainReturnStillPastesAsCopied() {
        let command = ClipPanelKeyMap.command(keyCode: 36, modifiers: [], axis: .vertical, searchIsEmpty: true)
        #expect(command == .paste)
    }
}

@Suite struct CopySoundSettingsTests {
    @Test func theCopySoundIsTheSoftOneAtHalfVolumeUntilChanged() {
        let store = ClipboardSettingsStore(defaults: InMemoryDefaults())
        #expect(store.copySound == .tink)
        #expect(store.copySoundVolume == 0.5)
    }

    @Test func theSoundAndItsVolumeAreRemembered() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        store.copySound = .purr
        store.copySoundVolume = 0.2
        #expect(ClipboardSettingsStore(defaults: defaults).copySound == .purr)
        #expect(ClipboardSettingsStore(defaults: defaults).copySoundVolume == 0.2)
    }

    @Test func theVolumeStaysWithinRange() {
        let store = ClipboardSettingsStore(defaults: InMemoryDefaults())
        store.copySoundVolume = 7
        #expect(store.copySoundVolume == 1)
        store.copySoundVolume = 0
        #expect(store.copySoundVolume == 0.05)
    }

    @Test func aSoundThatNoLongerExistsFallsBack() {
        let defaults = InMemoryDefaults()
        defaults.set("gong", forKey: ClipboardSettingsStore.Key.copySound)
        #expect(ClipboardSettingsStore(defaults: defaults).copySound == .tink)
    }
}

@Suite struct QuickPasteBoardSettingTests {
    @Test func noBoardIsChosenAtFirst() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.quickPasteBoardName == nil)
        store.quickPasteBoardName = "Công việc"
        #expect(ClipboardSettingsStore(defaults: defaults).quickPasteBoardName == "Công việc")
        store.quickPasteBoardName = nil
        #expect(ClipboardSettingsStore(defaults: defaults).quickPasteBoardName == nil)
    }
}

@Suite struct SelectAllTests {
    @Test func selectAllTakesEveryClipShown() {
        var selection = ClipMultiSelection()
        selection.selectAll(in: [5, 3, 9])
        #expect(selection.ids == [5, 3, 9])
        #expect(selection.primary == 5)
    }

    @Test func selectAllOnAnEmptyListSelectsNothing() {
        var selection = ClipMultiSelection()
        selection.click(4, in: [4])
        selection.selectAll(in: [])
        #expect(selection.ids.isEmpty)
        #expect(selection.primary == nil)
    }
}

@Suite struct ImageTextSettingTests {
    @Test func textInImagesIsReadUnlessTurnedOff() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.readsTextInImages == true)
        store.readsTextInImages = false
        #expect(ClipboardSettingsStore(defaults: defaults).readsTextInImages == false)
    }
}
