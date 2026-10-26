import Foundation
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func withStore(maxItems: Int = 500, _ body: (ClipboardStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-backup-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(try ClipboardStore(directory: directory, inMemory: true, maxItems: maxItems))
}

private let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
private let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])

/// A store with one clip of every kind, a link preview, rich text and two boards.
private func fill(_ store: ClipboardStore) throws {
    try store.add(.image(png), source: notes, at: date(10))
    try store.add(.files(["/tmp/a.txt", "/tmp/b.txt"]), source: notes, at: date(20))
    let link = try #require(try store.add(.text("https://example.com/"), source: notes, at: date(30)))
    try store.setLinkPreview(id: link.id, title: "Example", imageData: Data([9, 9]), at: date(31))
    let colour = try #require(try store.add(.text("#4A90D9"), source: notes, at: date(40)))
    let note = try #require(try store.add(
        .text("Hạn nộp: thứ Sáu"), rich: ClipRichData(rtf: Data([1, 2]), html: Data([3])),
        source: notes, at: date(50)))
    try store.touch(id: note.id, at: date(60))

    let work = try store.createBoard(name: "Công việc", symbolName: "briefcase", at: date(70))
    let design = try store.createBoard(name: "Thiết kế", symbolName: "paintbrush", at: date(71))
    try store.pin(itemID: note.id, toBoard: work.id, at: date(72))
    try store.pin(itemID: colour.id, toBoard: work.id, at: date(73))
    try store.pin(itemID: colour.id, toBoard: design.id, at: date(74))
}

@Suite struct ClipBackupTests {
    @Test func backupHoldsEveryClipWithItsFilesAndBoards() throws {
        try withStore { store in
            try fill(store)
            let backup = try store.makeBackup(at: date(100))

            #expect(backup.exportedAt == date(100))
            #expect(backup.boards == [
                .init(name: "Công việc", symbolName: "briefcase"),
                .init(name: "Thiết kế", symbolName: "paintbrush"),
            ])
            #expect(backup.items.map(\.kind) == ["text", "color", "link", "file", "image"])

            let note = backup.items[0]
            #expect(note.text == "Hạn nộp: thứ Sáu")
            #expect(note.rtf == Data([1, 2]))
            #expect(note.html == Data([3]))
            #expect(note.createdAt == date(50))
            #expect(note.lastUsedAt == date(60))
            #expect(note.sourceBundleID == "com.apple.Notes")
            #expect(note.sourceAppName == "Notes")
            #expect(note.boards == ["Công việc"])

            #expect(backup.items[1].boards == ["Công việc", "Thiết kế"])
            #expect(backup.items[2].linkTitle == "Example")
            #expect(backup.items[2].linkImage == Data([9, 9]))
            #expect(backup.items[2].linkCheckedAt == date(31))
            #expect(backup.items[3].text == "/tmp/a.txt\n/tmp/b.txt")
            #expect(backup.items[4].image == png)
        }
    }

    @Test func backupSurvivesEncodingToAFile() throws {
        try withStore { store in
            try fill(store)
            let backup = try store.makeBackup(at: date(100))
            let decoded = try ClipBackup.decode(try backup.encoded())
            #expect(decoded == backup)
        }
    }

    @Test func restoringIntoAnEmptyStoreRebuildsHistoryAndBoards() throws {
        try withStore { original in
            try fill(original)
            let backup = try original.makeBackup(at: date(100))

            try withStore { store in
                let summary = try store.restore(backup, at: date(200))
                #expect(summary == ClipBackupSummary(itemsAdded: 5, itemsAlreadyPresent: 0, itemsSkipped: 0, boardsAdded: 2))

                // The same content, in the same order, with the same dates.
                #expect(try store.makeBackup(at: date(100)) == backup)
                let items = try store.items()
                #expect(items.map(\.lastUsedAt) == [date(60), date(40), date(30), date(20), date(10)])
                #expect(store.imageData(for: items[4]) == png)
                #expect(store.richData(for: items[0]) == ClipRichData(rtf: Data([1, 2]), html: Data([3])))
            }
        }
    }

    @Test func restoringTwiceAddsNothingNew() throws {
        try withStore { store in
            try fill(store)
            let backup = try store.makeBackup(at: date(100))
            let summary = try store.restore(backup, at: date(200))
            #expect(summary == ClipBackupSummary(itemsAdded: 0, itemsAlreadyPresent: 5, itemsSkipped: 0, boardsAdded: 0))
            #expect(try store.makeBackup(at: date(100)) == backup)
        }
    }

    @Test func restoringMergesWithWhatIsAlreadyThere() throws {
        try withStore { original in
            try fill(original)
            let backup = try original.makeBackup(at: date(100))

            try withStore { store in
                // Same name in another letter case: the existing board is used.
                try store.createBoard(name: "công việc", symbolName: "star", at: date(1))
                let mine = try #require(try store.add(.text("của tôi"), source: notes, at: date(500)))
                let shared = try #require(try store.add(.text("#4A90D9"), source: notes, at: date(501)))

                let summary = try store.restore(backup, at: date(600))
                #expect(summary == ClipBackupSummary(itemsAdded: 4, itemsAlreadyPresent: 1, itemsSkipped: 0, boardsAdded: 1))

                try #expect(store.boards().map(\.name) == ["công việc", "Thiết kế"])
                let items = try store.items()
                #expect(items.count == 6)
                // Clips that were here keep their place and date.
                #expect(items.prefix(2).map(\.id) == [shared.id, mine.id])
                #expect(items[0].lastUsedAt == date(501))
                // The clip that was already present is still pinned as the backup says.
                let work = try #require(try store.boards().first)
                try #expect(store.items(inBoard: work.id).map(\.text).sorted() == ["#4A90D9", "Hạn nộp: thứ Sáu"])
            }
        }
    }

    @Test func restoredPinnedClipsSurviveASmallHistoryLimit() throws {
        try withStore { original in
            try fill(original)
            let backup = try original.makeBackup(at: date(100))

            try withStore(maxItems: 2) { store in
                try store.add(.text("mới nhất"), source: notes, at: date(900))
                try store.restore(backup, at: date(1000))
                // Two pinned clips, plus the two newest unpinned ones.
                try #expect(store.items().map(\.text) == ["mới nhất", "Hạn nộp: thứ Sáu", "#4A90D9", "https://example.com/"])
            }
        }
    }

    @Test func vaultClipsAndLockedBoardsStayOutOfTheBackup() throws {
        try withStore { store in
            try fill(store)
            let work = try #require(try store.boards().first)
            try store.createVault(passcode: "1234")
            try store.setBoardLocked(id: work.id, true)

            for _ in 0..<2 {
                let backup = try store.makeBackup(at: date(100))
                #expect(backup.boards.map(\.name) == ["Thiết kế"])
                #expect(!backup.items.map(\.text).contains("Hạn nộp: thứ Sáu"))
                #expect(!backup.items.map(\.text).contains("#4A90D9"))
                #expect(backup.items.count == 3)
                store.lockVault()
            }
        }
    }

    @Test func restoringNeverPinsToALockedBoard() throws {
        try withStore { original in
            try fill(original)
            let backup = try original.makeBackup(at: date(100))

            try withStore { store in
                let work = try store.createBoard(name: "Công việc", symbolName: "lock", at: date(1))
                try store.createVault(passcode: "1234")
                try store.setBoardLocked(id: work.id, true)
                store.lockVault()

                let summary = try store.restore(backup, at: date(200))
                #expect(summary.itemsAdded == 5)
                #expect(summary.boardsAdded == 1)
                // Everything landed in the plain history; nothing went into the vault.
                try #expect(store.items().count == 5)
                try #expect(store.boards().first?.itemCount == 0)
            }
        }
    }

    @Test func unusableEntriesAreSkipped() throws {
        try withStore { store in
            var backup = ClipBackup(exportedAt: date(1), boards: [], items: [])
            backup.items = [
                .init(kind: "image", text: "", createdAt: date(1), lastUsedAt: date(1)),
                .init(kind: "text", text: "   ", createdAt: date(1), lastUsedAt: date(1)),
                .init(kind: "hologram", text: "x", createdAt: date(1), lastUsedAt: date(1)),
                .init(kind: "text", text: "dùng được", createdAt: date(1), lastUsedAt: date(2)),
            ]
            let summary = try store.restore(backup, at: date(10))
            #expect(summary == ClipBackupSummary(itemsAdded: 1, itemsAlreadyPresent: 0, itemsSkipped: 3, boardsAdded: 0))
        }
    }

    @Test func aFileThatIsNotABackupIsRejected() {
        #expect(throws: ClipBackupError.notABackup) { try ClipBackup.decode(Data("xin chào".utf8)) }
        #expect(throws: ClipBackupError.notABackup) { try ClipBackup.decode(Data(#"{"format":"other","version":1}"#.utf8)) }
    }

    @Test func aBackupFromANewerVersionIsRejected() throws {
        var backup = ClipBackup(exportedAt: date(1), boards: [], items: [])
        backup.version = ClipBackup.currentVersion + 1
        let data = try backup.encoded()
        #expect(throws: ClipBackupError.newerVersion(ClipBackup.currentVersion + 1)) { try ClipBackup.decode(data) }
    }
}

@Suite struct ClipBackupTitleTests {
    @Test func aBackupCarriesTheTitlesOfClips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-backup-title-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try ClipboardStore(directory: directory.appendingPathComponent("a"), inMemory: true, maxItems: 500)
        let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
        let item = try #require(try source.add(.text("0912 345 678"), source: notes, at: Date(timeIntervalSince1970: 1)))
        try source.setTitle(id: item.id, title: "Số của anh Minh")
        let backup = try source.makeBackup(at: Date(timeIntervalSince1970: 2))

        let target = try ClipboardStore(directory: directory.appendingPathComponent("b"), inMemory: true, maxItems: 500)
        _ = try target.restore(backup, at: Date(timeIntervalSince1970: 3))
        #expect(try target.items().first?.title == "Số của anh Minh")
    }
}

