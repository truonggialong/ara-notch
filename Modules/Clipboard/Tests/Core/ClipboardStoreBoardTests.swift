import Foundation
import SQLite3
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-board-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func withStore(maxItems: Int = 500, _ body: (ClipboardStore, URL) throws -> Void) throws {
    try withDirectory { directory in
        try body(try ClipboardStore(directory: directory, inMemory: true, maxItems: maxItems), directory)
    }
}

private func blobFiles(in directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("blobs").path)) ?? []
}

private let source = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")

@discardableResult
private func addText(_ store: ClipboardStore, _ text: String, at seconds: TimeInterval) throws -> ClipItem {
    try #require(try store.add(.text(text), source: source, at: date(seconds)))
}

@Suite struct BoardManagementTests {
    @Test func noBoardsAtFirst() throws {
        try withStore { store, _ in
            try #expect(store.boards().isEmpty)
            try #expect(store.boardMembership().isEmpty)
        }
    }

    @Test func createdBoardsAreListedInCreationOrder() throws {
        try withStore { store, _ in
            let work = try store.createBoard(name: "Công việc", symbolName: "briefcase", at: date(1))
            try store.createBoard(name: "Code", symbolName: "star", at: date(2))
            #expect(work.name == "Công việc")
            #expect(work.symbolName == "briefcase")
            #expect(work.itemCount == 0)
            try #expect(store.boards().map(\.name) == ["Công việc", "Code"])
        }
    }

    @Test func nameIsTrimmed() throws {
        try withStore { store, _ in
            try #expect(store.createBoard(name: "  Việc \n", symbolName: "pin", at: date(1)).name == "Việc")
        }
    }

    @Test(arguments: ["", "   ", "\n\t", String(repeating: "a", count: 41)])
    func invalidNamesAreRejected(_ name: String) throws {
        try withStore { store, _ in
            #expect(throws: ClipboardStoreError.invalidBoardName) {
                try store.createBoard(name: name, symbolName: "pin", at: date(1))
            }
            try #expect(store.boards().isEmpty)
        }
    }

    @Test func nameOf40CharactersIsAccepted() throws {
        try withStore { store, _ in
            let name = String(repeating: "á", count: 40)
            try #expect(store.createBoard(name: name, symbolName: "pin", at: date(1)).name == name)
        }
    }

    @Test func duplicateNamesAreRejectedIgnoringCaseAndPadding() throws {
        try withStore { store, _ in
            try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            for name in ["Việc", " việc ", "VIỆC"] {
                #expect(throws: ClipboardStoreError.duplicateBoardName) {
                    try store.createBoard(name: name, symbolName: "pin", at: date(2))
                }
            }
            try #expect(store.boards().count == 1)
        }
    }

    @Test func boardLimitIsEnforced() throws {
        try withStore { store, _ in
            for index in 1...20 {
                try store.createBoard(name: "Board \(index)", symbolName: "pin", at: date(Double(index)))
            }
            #expect(throws: ClipboardStoreError.tooManyBoards) {
                try store.createBoard(name: "Board 21", symbolName: "pin", at: date(21))
            }
        }
    }

    @Test func updateChangesNameAndSymbol() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Cũ", symbolName: "pin", at: date(1))
            try store.updateBoard(id: board.id, name: " Mới ", symbolName: "star")
            let updated = try #require(try store.boards().first)
            #expect(updated.name == "Mới")
            #expect(updated.symbolName == "star")
        }
    }

    @Test func updateEnforcesTheNameRules() throws {
        try withStore { store, _ in
            let first = try store.createBoard(name: "Một", symbolName: "pin", at: date(1))
            try store.createBoard(name: "Hai", symbolName: "pin", at: date(2))
            #expect(throws: ClipboardStoreError.duplicateBoardName) {
                try store.updateBoard(id: first.id, name: "hai", symbolName: "pin")
            }
            #expect(throws: ClipboardStoreError.invalidBoardName) {
                try store.updateBoard(id: first.id, name: " ", symbolName: "pin")
            }
            // Keeping its own name, even in another case, is not a duplicate.
            try store.updateBoard(id: first.id, name: "MỘT", symbolName: "star")
            try #expect(store.boards().map(\.name) == ["MỘT", "Hai"])
        }
    }

    @Test func deleteBoardKeepsItsItemsInHistory() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let item = try addText(store, "giữ lại", at: 2)
            try store.pin(itemID: item.id, toBoard: board.id, at: date(3))
            try store.deleteBoard(id: board.id)
            try #expect(store.boards().isEmpty)
            try #expect(store.items().map(\.text) == ["giữ lại"])
            try #expect(store.boardMembership().isEmpty)
        }
    }
}

@Suite struct BoardPinningTests {
    @Test func pinnedItemsAreListedMostRecentPinFirst() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let a = try addText(store, "a", at: 2)
            let b = try addText(store, "b", at: 3)
            try store.pin(itemID: b.id, toBoard: board.id, at: date(10))
            try store.pin(itemID: a.id, toBoard: board.id, at: date(11))
            try #expect(store.items(inBoard: board.id).map(\.text) == ["a", "b"])
            try #expect(store.boards().first?.itemCount == 2)
        }
    }

    @Test func pinningAgainChangesNothing() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let a = try addText(store, "a", at: 2)
            let b = try addText(store, "b", at: 3)
            try store.pin(itemID: a.id, toBoard: board.id, at: date(10))
            try store.pin(itemID: b.id, toBoard: board.id, at: date(11))
            try store.pin(itemID: a.id, toBoard: board.id, at: date(12))
            try #expect(store.items(inBoard: board.id).map(\.text) == ["b", "a"])
        }
    }

    @Test func pinningUnknownItemOrBoardIsIgnored() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let item = try addText(store, "a", at: 2)
            try store.pin(itemID: 999, toBoard: board.id, at: date(3))
            try store.pin(itemID: item.id, toBoard: 999, at: date(3))
            try #expect(store.items(inBoard: board.id).isEmpty)
            try #expect(store.boardMembership().isEmpty)
        }
    }

    @Test func fullBoardRejectsAnotherPin() throws {
        try withStore(maxItems: 1000) { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            for index in 1...200 {
                let item = try addText(store, "mục \(index)", at: Double(index))
                try store.pin(itemID: item.id, toBoard: board.id, at: date(Double(index)))
            }
            let extra = try addText(store, "thừa", at: 500)
            #expect(throws: ClipboardStoreError.boardFull) {
                try store.pin(itemID: extra.id, toBoard: board.id, at: date(501))
            }
            try #expect(store.boards().first?.itemCount == 200)
        }
    }

    @Test func membershipListsEveryBoardOfAnItem() throws {
        try withStore { store, _ in
            let one = try store.createBoard(name: "Một", symbolName: "pin", at: date(1))
            let two = try store.createBoard(name: "Hai", symbolName: "pin", at: date(2))
            let item = try addText(store, "chung", at: 3)
            let other = try addText(store, "riêng", at: 4)
            try store.pin(itemID: item.id, toBoard: one.id, at: date(5))
            try store.pin(itemID: item.id, toBoard: two.id, at: date(6))
            try store.pin(itemID: other.id, toBoard: two.id, at: date(7))
            try #expect(store.boardMembership() == [item.id: [one.id, two.id], other.id: [two.id]])
        }
    }

    @Test func unpinningFromOneBoardKeepsTheOther() throws {
        try withStore { store, _ in
            let one = try store.createBoard(name: "Một", symbolName: "pin", at: date(1))
            let two = try store.createBoard(name: "Hai", symbolName: "pin", at: date(2))
            let item = try addText(store, "chung", at: 3)
            try store.pin(itemID: item.id, toBoard: one.id, at: date(5))
            try store.pin(itemID: item.id, toBoard: two.id, at: date(6))
            try store.unpin(itemID: item.id, fromBoard: one.id)
            try #expect(store.items(inBoard: one.id).isEmpty)
            try #expect(store.items(inBoard: two.id).map(\.text) == ["chung"])
        }
    }

    @Test func deletingAnItemRemovesItFromBoards() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let item = try addText(store, "a", at: 2)
            try store.pin(itemID: item.id, toBoard: board.id, at: date(3))
            try store.delete(id: item.id)
            try #expect(store.items(inBoard: board.id).isEmpty)
            try #expect(store.boards().first?.itemCount == 0)
            try #expect(store.boardMembership().isEmpty)
        }
    }

    @Test func recopyingAPinnedItemKeepsItPinned() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let item = try addText(store, "a", at: 2)
            try store.pin(itemID: item.id, toBoard: board.id, at: date(3))
            try addText(store, "a", at: 9)
            try #expect(store.items(inBoard: board.id).map(\.id) == [item.id])
        }
    }
}

@Suite struct BoardRetentionTests {
    @Test func pinnedItemsSurvivePruning() throws {
        try withStore(maxItems: 2) { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let oldest = try addText(store, "ghim", at: 2)
            try store.pin(itemID: oldest.id, toBoard: board.id, at: date(3))
            for index in 1...5 {
                try addText(store, "mục \(index)", at: Double(10 + index))
            }
            try #expect(store.items().map(\.text) == ["mục 5", "mục 4", "ghim"])
        }
    }

    @Test func loweringMaxItemsNeverCutsPinnedItems() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            for index in 1...4 {
                let item = try addText(store, "mục \(index)", at: Double(index))
                if index <= 2 { try store.pin(itemID: item.id, toBoard: board.id, at: date(Double(index))) }
            }
            try store.setMaxItems(1)
            try #expect(store.items().map(\.text) == ["mục 4", "mục 2", "mục 1"])
        }
    }

    @Test func deleteAllKeepsPinnedItemsAndTheirFiles() throws {
        try withStore { store, directory in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let pinnedImage = try #require(try store.add(.image(Data([1, 2, 3])), source: source, at: date(2)))
            try store.add(.image(Data([4, 5, 6])), source: source, at: date(3))
            try addText(store, "thường", at: 4)
            try store.pin(itemID: pinnedImage.id, toBoard: board.id, at: date(5))

            try store.deleteAll()

            try #expect(store.items().map(\.id) == [pinnedImage.id])
            let pinnedBlob = try #require(pinnedImage.blobName)
            #expect(blobFiles(in: directory) == [pinnedBlob])
            #expect(store.imageData(for: pinnedImage) == Data([1, 2, 3]))
            try #expect(store.boards().first?.itemCount == 1)
        }
    }

    @Test func unpinningWhenHistoryIsFullPrunesTheOldItem() throws {
        try withStore(maxItems: 2) { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let oldest = try addText(store, "cũ", at: 2)
            try store.pin(itemID: oldest.id, toBoard: board.id, at: date(3))
            try addText(store, "a", at: 10)
            try addText(store, "b", at: 11)
            try store.unpin(itemID: oldest.id, fromBoard: board.id)
            try #expect(store.items().map(\.text) == ["b", "a"])
        }
    }

    @Test func deletingABoardPrunesItsFormerItems() throws {
        try withStore(maxItems: 1) { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let oldest = try addText(store, "cũ", at: 2)
            try store.pin(itemID: oldest.id, toBoard: board.id, at: date(3))
            try addText(store, "mới", at: 10)
            try store.deleteBoard(id: board.id)
            try #expect(store.items().map(\.text) == ["mới"])
        }
    }
}

@Suite struct BoardPersistenceTests {
    @Test func boardsAndPinsSurviveReopen() throws {
        try withDirectory { directory in
            do {
                let store = try ClipboardStore(directory: directory)
                let board = try store.createBoard(name: "Việc", symbolName: "briefcase", at: date(1))
                let item = try addText(store, "ghim", at: 2)
                try store.pin(itemID: item.id, toBoard: board.id, at: date(3))
            }
            let reopened = try ClipboardStore(directory: directory)
            let board = try #require(try reopened.boards().first)
            #expect(board.name == "Việc")
            #expect(board.symbolName == "briefcase")
            try #expect(reopened.items(inBoard: board.id).map(\.text) == ["ghim"])
        }
    }

    @Test func migratesVersion3Store() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("blobs"), withIntermediateDirectories: true)
            var handle: OpaquePointer?
            let path = directory.appendingPathComponent("clipboard.sqlite").path
            #expect(sqlite3_open(path, &handle) == SQLITE_OK)
            let sql = """
                CREATE TABLE items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, text TEXT NOT NULL,
                    blob_name TEXT, content_hash TEXT NOT NULL UNIQUE, source_bundle_id TEXT,
                    source_app_name TEXT, created_at REAL NOT NULL, last_used_at REAL NOT NULL,
                    byte_size INTEGER NOT NULL, rtf_blob TEXT, html_blob TEXT,
                    link_title TEXT, link_image_blob TEXT, link_checked_at REAL);
                INSERT INTO items (kind, text, content_hash, created_at, last_used_at, byte_size)
                    VALUES ('text', 'cũ', 'h1', 1, 1, 3);
                PRAGMA user_version = 3;
                """
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(handle)

            let store = try ClipboardStore(directory: directory)
            let item = try #require(try store.items().first)
            #expect(item.text == "cũ")
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(2))
            try store.pin(itemID: item.id, toBoard: board.id, at: date(3))
            try #expect(store.items(inBoard: board.id).map(\.text) == ["cũ"])
        }
    }
}

@Suite struct BoardOrderTests {
    /// A board with clips a, b, c pinned in that order, so it lists c, b, a.
    private func withBoard(_ body: (ClipboardStore, Int64, [String: Int64]) throws -> Void) throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            var ids: [String: Int64] = [:]
            for (offset, text) in ["a", "b", "c"].enumerated() {
                let item = try addText(store, text, at: Double(10 + offset))
                try store.pin(itemID: item.id, toBoard: board.id, at: date(Double(20 + offset)))
                ids[text] = item.id
            }
            try body(store, board.id, ids)
        }
    }

    private func order(_ store: ClipboardStore, _ boardID: Int64) throws -> [String] {
        try store.items(inBoard: boardID).map(\.text)
    }

    @Test func movingAClipPutsItBeforeAnother() throws {
        try withBoard { store, board, ids in
            try #expect(order(store, board) == ["c", "b", "a"])
            try store.moveItem(try #require(ids["a"]), inBoard: board, before: ids["c"], at: date(100))
            try #expect(order(store, board) == ["a", "c", "b"])
            try store.moveItem(try #require(ids["c"]), inBoard: board, before: ids["b"], at: date(101))
            try #expect(order(store, board) == ["a", "c", "b"])
            try store.moveItem(try #require(ids["a"]), inBoard: board, before: ids["b"], at: date(102))
            try #expect(order(store, board) == ["c", "a", "b"])
        }
    }

    @Test func movingWithoutATargetPutsTheClipLast() throws {
        try withBoard { store, board, ids in
            try store.moveItem(try #require(ids["c"]), inBoard: board, before: nil, at: date(100))
            try #expect(order(store, board) == ["b", "a", "c"])
        }
    }

    @Test func aLaterPinStillGoesFirst() throws {
        try withBoard { store, board, ids in
            try store.moveItem(try #require(ids["a"]), inBoard: board, before: ids["c"], at: date(100))
            let fresh = try addText(store, "d", at: 200)
            try store.pin(itemID: fresh.id, toBoard: board, at: date(201))
            try #expect(order(store, board) == ["d", "a", "c", "b"])
        }
    }

    @Test func movesThatMakeNoSenseChangeNothing() throws {
        try withBoard { store, board, ids in
            let stranger = try addText(store, "x", at: 50)
            try store.moveItem(stranger.id, inBoard: board, before: ids["a"], at: date(100))
            try store.moveItem(try #require(ids["a"]), inBoard: board, before: stranger.id, at: date(100))
            try store.moveItem(try #require(ids["a"]), inBoard: board, before: ids["a"], at: date(100))
            try store.moveItem(try #require(ids["a"]), inBoard: 999, before: ids["b"], at: date(100))
            try #expect(order(store, board) == ["c", "b", "a"])
            try #expect(store.items(inBoard: board).count == 3)
        }
    }

    @Test func aLockedBoardNeedsTheVaultUnlocked() throws {
        try withBoard { store, board, ids in
            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: board, true)
            try store.moveItem(try #require(ids["a"]), inBoard: board, before: ids["c"], at: date(100))
            try #expect(order(store, board) == ["a", "c", "b"])
            store.lockVault()
            #expect(throws: ClipboardStoreError.vaultLocked) {
                try store.moveItem(try #require(ids["b"]), inBoard: board, before: ids["a"], at: date(101))
            }
        }
    }
}
