import Foundation
import SQLite3
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-vault-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func withStore(_ body: (ClipboardStore, URL) throws -> Void) throws {
    try withDirectory { directory in
        try body(try ClipboardStore(directory: directory, inMemory: true), directory)
    }
}

private func blobFiles(in directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("blobs").path)) ?? []
}

private func contains(_ haystack: Data, _ needle: String) -> Bool {
    haystack.range(of: Data(needle.utf8)) != nil
}

private let source = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
private let secret = "Mật khẩu wifi: hoa-sen-2026"
private let picture = Data("PNG-ẢNH-BÍ-MẬT-0123456789".utf8)

/// A store with one board holding the secret text, the vault created and the board locked.
private func lockedSetup(_ store: ClipboardStore) throws -> (board: ClipBoard, item: ClipItem) {
    let board = try store.createBoard(name: "Riêng tư", symbolName: "pin", at: date(1))
    let item = try #require(try store.add(.text(secret), source: source, at: date(2)))
    try store.pin(itemID: item.id, toBoard: board.id, at: date(3))
    try store.createVault(passcode: "1234")
    try store.setBoardLocked(id: board.id, true)
    return (try #require(try store.boards().first), item)
}

@Suite struct VaultLifecycleTests {
    @Test func vaultStartsNotSetUp() throws {
        try withStore { store, _ in
            #expect(store.vaultState == .notSetUp)
            #expect(throws: ClipboardStoreError.vaultNotSetUp) { try store.unlockVault(passcode: "1234") }
        }
    }

    @Test func creatingAVaultUnlocksIt() throws {
        try withStore { store, _ in
            try store.createVault(passcode: "1234")
            #expect(store.vaultState == .unlocked)
            #expect(throws: ClipboardStoreError.vaultAlreadyExists) { try store.createVault(passcode: "5678") }
        }
    }

    @Test(arguments: ["", "1", "123"])
    func shortPasscodeIsRejected(_ passcode: String) throws {
        try withStore { store, _ in
            #expect(throws: ClipboardStoreError.invalidPasscode) { try store.createVault(passcode: passcode) }
            #expect(store.vaultState == .notSetUp)
        }
    }

    @Test func lockAndUnlock() throws {
        try withStore { store, _ in
            try store.createVault(passcode: "1234")
            store.lockVault()
            #expect(store.vaultState == .locked)
            #expect(throws: ClipboardStoreError.wrongPasscode) { try store.unlockVault(passcode: "0000") }
            #expect(store.vaultState == .locked)
            try store.unlockVault(passcode: "1234")
            #expect(store.vaultState == .unlocked)
        }
    }

    @Test func changingThePasscodeKeepsTheContentReadable() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            #expect(throws: ClipboardStoreError.wrongPasscode) {
                try store.changeVaultPasscode(from: "sai!", to: "5678")
            }
            #expect(throws: ClipboardStoreError.invalidPasscode) {
                try store.changeVaultPasscode(from: "1234", to: "12")
            }
            try store.changeVaultPasscode(from: "1234", to: "5678")
            store.lockVault()
            #expect(throws: ClipboardStoreError.wrongPasscode) { try store.unlockVault(passcode: "1234") }
            try store.unlockVault(passcode: "5678")
            try #expect(store.items(inBoard: setup.board.id).map(\.text) == [secret])
        }
    }
}

@Suite struct LockedBoardTests {
    @Test func lockingABoardHidesItsItemsFromTheHistory() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            #expect(setup.board.isLocked)
            #expect(setup.board.itemCount == 1)
            try #expect(store.items().isEmpty)
            let items = try store.items(inBoard: setup.board.id)
            #expect(items.map(\.text) == [secret])
            #expect(items.first?.isEncrypted == true)
            #expect(items.first?.kind == .text)
        }
    }

    @Test func lockedVaultRefusesToShowTheBoard() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            store.lockVault()
            #expect(throws: ClipboardStoreError.vaultLocked) { try store.items(inBoard: setup.board.id) }
            try #expect(store.items().isEmpty)
            try #expect(store.item(id: setup.item.id) == nil)
            try store.unlockVault(passcode: "1234")
            try #expect(store.items(inBoard: setup.board.id).map(\.text) == [secret])
        }
    }

    @Test func lockingNeedsAnUnlockedVault() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Riêng tư", symbolName: "pin", at: date(1))
            #expect(throws: ClipboardStoreError.vaultLocked) { try store.setBoardLocked(id: board.id, true) }
            try store.createVault(passcode: "1234")
            store.lockVault()
            #expect(throws: ClipboardStoreError.vaultLocked) { try store.setBoardLocked(id: board.id, true) }
            try #expect(store.boards().first?.isLocked == false)
        }
    }

    @Test func operationsOnALockedBoardNeedAnUnlockedVault() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            let other = try #require(try store.add(.text("khác"), source: source, at: date(9)))
            store.lockVault()

            #expect(throws: ClipboardStoreError.vaultLocked) {
                try store.pin(itemID: other.id, toBoard: setup.board.id, at: date(10))
            }
            #expect(throws: ClipboardStoreError.vaultLocked) {
                try store.unpin(itemID: setup.item.id, fromBoard: setup.board.id)
            }
            #expect(throws: ClipboardStoreError.vaultLocked) { try store.deleteBoard(id: setup.board.id) }
            #expect(throws: ClipboardStoreError.vaultLocked) { try store.setBoardLocked(id: setup.board.id, false) }

            try #expect(store.boards().first?.itemCount == 1)
            try #expect(store.items().map(\.text) == ["khác"])
        }
    }

    @Test func pinningToALockedBoardMovesTheItemIntoTheVault() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            let open = try store.createBoard(name: "Thường", symbolName: "pin", at: date(4))
            let item = try #require(try store.add(.text("thêm vào két"), source: source, at: date(5)))
            try store.pin(itemID: item.id, toBoard: open.id, at: date(6))
            try store.pin(itemID: item.id, toBoard: setup.board.id, at: date(7))

            try #expect(store.items().isEmpty)
            try #expect(store.items(inBoard: open.id).isEmpty)
            try #expect(store.items(inBoard: setup.board.id).map(\.text) == ["thêm vào két", secret])
        }
    }

    @Test func vaultItemsCannotBePinnedToAnOpenBoard() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            let open = try store.createBoard(name: "Thường", symbolName: "pin", at: date(4))
            try store.pin(itemID: setup.item.id, toBoard: open.id, at: date(5))
            try #expect(store.items(inBoard: open.id).isEmpty)
        }
    }

    @Test func unpinningReturnsTheItemToTheHistory() throws {
        try withStore { store, directory in
            let setup = try lockedSetup(store)
            try store.unpin(itemID: setup.item.id, fromBoard: setup.board.id)
            let items = try store.items()
            #expect(items.map(\.text) == [secret])
            #expect(items.first?.isEncrypted == false)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func unlockingTheBoardReturnsItsItemsToTheHistoryStillPinned() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            try store.setBoardLocked(id: setup.board.id, false)
            try #expect(store.boards().first?.isLocked == false)
            try #expect(store.items().map(\.text) == [secret])
            try #expect(store.items(inBoard: setup.board.id).map(\.text) == [secret])
        }
    }

    @Test func itemInTwoLockedBoardsStaysInTheVaultUntilBothRelease() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            let second = try store.createBoard(name: "Két hai", symbolName: "pin", at: date(4))
            try store.setBoardLocked(id: second.id, true)
            try store.pin(itemID: setup.item.id, toBoard: second.id, at: date(5))

            try store.unpin(itemID: setup.item.id, fromBoard: setup.board.id)
            try #expect(store.items().isEmpty)
            try #expect(store.items(inBoard: second.id).map(\.text) == [secret])

            try store.setBoardLocked(id: second.id, false)
            try #expect(store.items().map(\.text) == [secret])
        }
    }

    @Test func returningItemMergesWithAnIdenticalHistoryItem() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            // Copied again while the original sits in the vault: an ordinary, separate entry.
            let again = try #require(try store.add(.text(secret), source: source, at: date(20)))
            #expect(again.id != setup.item.id)
            try #expect(store.items().map(\.text) == [secret])

            try store.setBoardLocked(id: setup.board.id, false)
            let items = try store.items()
            #expect(items.map(\.text) == [secret])
            try #expect(store.items(inBoard: setup.board.id).map(\.id) == items.map(\.id))
            try #expect(store.boards().first?.itemCount == 1)
        }
    }

    @Test func deletingALockedBoardReturnsItsItems() throws {
        try withStore { store, _ in
            let setup = try lockedSetup(store)
            try store.deleteBoard(id: setup.board.id)
            try #expect(store.boards().isEmpty)
            try #expect(store.items().map(\.text) == [secret])
        }
    }

    @Test func deletingAVaultItemWorksEvenWhenLocked() throws {
        try withStore { store, directory in
            let board = try store.createBoard(name: "Riêng tư", symbolName: "pin", at: date(1))
            let image = try #require(try store.add(.image(picture), source: source, at: date(2)))
            try store.pin(itemID: image.id, toBoard: board.id, at: date(3))
            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: board.id, true)
            store.lockVault()

            try store.delete(id: image.id)
            #expect(blobFiles(in: directory).isEmpty)
            try #expect(store.boards().first?.itemCount == 0)
        }
    }

    @Test func clearingAndPruningLeaveVaultItemsAlone() throws {
        try withDirectory { directory in
            let store = try ClipboardStore(directory: directory, inMemory: true, maxItems: 1)
            let setup = try lockedSetup(store)
            try store.add(.text("a"), source: source, at: date(30))
            try store.add(.text("b"), source: source, at: date(31))
            try store.deleteAll()
            try #expect(store.items(inBoard: setup.board.id).map(\.text) == [secret])
        }
    }
}

@Suite struct VaultStorageTests {
    @Test func lockedContentIsNotOnDiskInTheClear() throws {
        try withDirectory { directory in
            let store = try ClipboardStore(directory: directory)
            let board = try store.createBoard(name: "Riêng tư", symbolName: "pin", at: date(1))
            let text = try #require(try store.add(
                .text(secret), rich: ClipRichData(rtf: Data("RTF-BÍ-MẬT-abcdef".utf8)), source: source, at: date(2)))
            let image = try #require(try store.add(.image(picture), source: source, at: date(3)))
            let link = try #require(try store.add(.text("https://example.com/rieng-tu"), source: source, at: date(4)))
            try store.setLinkPreview(id: link.id, title: "Tiêu đề bí mật", imageData: Data("ẢNH-XEM-TRƯỚC-xyz".utf8), at: date(5))
            for id in [text.id, image.id, link.id] {
                try store.pin(itemID: id, toBoard: board.id, at: date(6))
            }
            let plainNames = Set(blobFiles(in: directory))
            #expect(plainNames.count == 3)

            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: board.id, true)

            let database = try Data(contentsOf: directory.appendingPathComponent("clipboard.sqlite"))
            for needle in [secret, "hoa-sen", "example.com/rieng-tu", "Tiêu đề bí mật"] {
                #expect(!contains(database, needle), "database still contains \(needle)")
            }
            let names = blobFiles(in: directory)
            #expect(names.count == 3)
            #expect(Set(names).isDisjoint(with: plainNames))
            for name in names {
                let file = try Data(contentsOf: directory.appendingPathComponent("blobs/\(name)"))
                for needle in ["PNG-ẢNH-BÍ-MẬT", "RTF-BÍ-MẬT", "ẢNH-XEM-TRƯỚC"] {
                    #expect(!contains(file, needle), "\(name) still contains \(needle)")
                }
            }

            // And everything is still readable through the unlocked vault.
            let items = try store.items(inBoard: board.id)
            #expect(Set(items.map(\.text)) == [secret, "", "https://example.com/rieng-tu"])
            let storedImage = try #require(items.first { $0.kind == .image })
            let storedText = try #require(items.first { $0.kind == .text })
            let storedLink = try #require(items.first { $0.kind == .link })
            #expect(store.imageData(for: storedImage) == picture)
            #expect(store.richData(for: storedText)?.rtf == Data("RTF-BÍ-MẬT-abcdef".utf8))
            #expect(storedLink.linkTitle == "Tiêu đề bí mật")
            #expect(store.linkImageData(for: storedLink) == Data("ẢNH-XEM-TRƯỚC-xyz".utf8))
        }
    }

    @Test func lockedVaultGivesNoBlobData() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Riêng tư", symbolName: "pin", at: date(1))
            let image = try #require(try store.add(.image(picture), source: source, at: date(2)))
            try store.pin(itemID: image.id, toBoard: board.id, at: date(3))
            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: board.id, true)
            let stored = try #require(try store.items(inBoard: board.id).first)
            #expect(store.imageData(for: stored) == picture)
            store.lockVault()
            #expect(store.imageData(for: stored) == nil)
        }
    }

    @Test func unlockingRestoresPlainFiles() throws {
        try withStore { store, directory in
            let board = try store.createBoard(name: "Riêng tư", symbolName: "pin", at: date(1))
            let image = try #require(try store.add(.image(picture), source: source, at: date(2)))
            let plainName = try #require(image.blobName)
            try store.pin(itemID: image.id, toBoard: board.id, at: date(3))
            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: board.id, true)
            #expect(blobFiles(in: directory) != [plainName])

            try store.setBoardLocked(id: board.id, false)
            #expect(blobFiles(in: directory) == [plainName])
            let restored = try #require(try store.items().first)
            #expect(store.imageData(for: restored) == picture)
        }
    }

    @Test func vaultIsLockedAfterReopenAndOpensWithThePasscode() throws {
        try withDirectory { directory in
            var boardID: Int64 = 0
            do {
                let store = try ClipboardStore(directory: directory)
                boardID = try lockedSetup(store).board.id
            }
            let reopened = try ClipboardStore(directory: directory)
            #expect(reopened.vaultState == .locked)
            try #expect(reopened.items().isEmpty)
            try #expect(reopened.boards().first?.isLocked == true)
            #expect(throws: ClipboardStoreError.vaultLocked) { try reopened.items(inBoard: boardID) }
            try reopened.unlockVault(passcode: "1234")
            try #expect(reopened.items(inBoard: boardID).map(\.text) == [secret])
        }
    }

    @Test func migratesVersion4Store() throws {
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
                CREATE TABLE boards (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    symbol TEXT NOT NULL, created_at REAL NOT NULL);
                CREATE TABLE board_items (board_id INTEGER NOT NULL, item_id INTEGER NOT NULL,
                    pinned_at REAL NOT NULL, PRIMARY KEY (board_id, item_id));
                INSERT INTO items (kind, text, content_hash, created_at, last_used_at, byte_size)
                    VALUES ('text', 'cũ', 'h1', 1, 1, 3);
                INSERT INTO boards (name, symbol, created_at) VALUES ('Việc', 'pin', 1);
                INSERT INTO board_items VALUES (1, 1, 2);
                PRAGMA user_version = 4;
                """
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(handle)

            let store = try ClipboardStore(directory: directory)
            let board = try #require(try store.boards().first)
            #expect(board.isLocked == false)
            try #expect(store.items().map(\.text) == ["cũ"])
            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: board.id, true)
            try #expect(store.items().isEmpty)
            try #expect(store.items(inBoard: board.id).map(\.text) == ["cũ"])
        }
    }
}
