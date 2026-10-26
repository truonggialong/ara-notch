import Foundation
import SQLite3
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

/// Runs the body with a fresh temporary directory and removes it afterwards.
private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-store-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

/// Runs the body with an in-memory store whose images live in a temporary directory.
private func withStore(maxItems: Int = 500, _ body: (ClipboardStore, URL) throws -> Void) throws {
    try withDirectory { directory in
        try body(try ClipboardStore(directory: directory, inMemory: true, maxItems: maxItems), directory)
    }
}

private func blobFiles(in directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("blobs").path)) ?? []
}

private let imageA = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
private let safari = ClipSource(bundleID: "com.apple.Safari", appName: "Safari")
private let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")

@Suite struct ClipboardStoreAddTests {
    @Test func addTextCreatesItem() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("hello"), source: safari, at: date(10)))
            #expect(item.kind == .text)
            #expect(item.text == "hello")
            #expect(item.byteSize == 5)
            #expect(item.createdAt == date(10))
            #expect(item.lastUsedAt == date(10))
            #expect(item.source == safari)
            try #expect(store.items() == [item])
        }
    }

    @Test func addClassifiesKinds() throws {
        try withStore { store, _ in
            try #expect(store.add(.text("https://example.com"), source: safari, at: date(1))?.kind == .link)
            try #expect(store.add(.text("#4A90D9"), source: safari, at: date(2))?.kind == .color)
            try #expect(store.add(.files(["/tmp/a.txt"]), source: safari, at: date(3))?.kind == .file)
            try #expect(store.add(.image(imageA), source: safari, at: date(4))?.kind == .image)
        }
    }

    @Test func itemsAreNewestFirst() throws {
        try withStore { store, _ in
            try store.add(.text("a"), source: safari, at: date(1))
            try store.add(.text("b"), source: safari, at: date(2))
            try store.add(.text("c"), source: safari, at: date(3))
            try #expect(store.items().map(\.text) == ["c", "b", "a"])
        }
    }

    @Test func itemsWithEqualDatesAreNewestInsertFirst() throws {
        try withStore { store, _ in
            try store.add(.text("a"), source: safari, at: date(1))
            try store.add(.text("b"), source: safari, at: date(1))
            try #expect(store.items().map(\.text) == ["b", "a"])
        }
    }

    @Test func duplicateMovesToTopAndUpdatesSource() throws {
        try withStore { store, _ in
            let first = try #require(try store.add(.text("a"), source: safari, at: date(1)))
            try store.add(.text("b"), source: safari, at: date(2))
            let again = try #require(try store.add(.text("a"), source: notes, at: date(3)))

            let items = try store.items()
            #expect(items.map(\.text) == ["a", "b"])
            #expect(again.id == first.id)
            #expect(items[0].source == notes)
            #expect(items[0].createdAt == date(1))
            #expect(items[0].lastUsedAt == date(3))
        }
    }

    @Test func sameTextDifferentKindIsNotDuplicate() throws {
        try withStore { store, _ in
            try store.add(.text("/tmp/a"), source: safari, at: date(1))
            try store.add(.files(["/tmp/a"]), source: safari, at: date(2))
            try #expect(store.items().map(\.kind) == [.file, .text])
        }
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func whitespaceOnlyTextIsRejected(_ text: String) throws {
        try withStore { store, _ in
            try #expect(store.add(.text(text), source: safari, at: date(1)) == nil)
            try #expect(store.items().isEmpty)
        }
    }

    @Test func oversizedTextIsRejected() throws {
        try withStore { store, _ in
            let limit = String(repeating: "a", count: 1_000_000)
            try #expect(store.add(.text(limit + "a"), source: safari, at: date(1)) == nil)
            try #expect(store.add(.text(limit), source: safari, at: date(2)) != nil)
        }
    }

    @Test func emptyFileListIsRejected() throws {
        try withStore { store, _ in
            try #expect(store.add(.files([]), source: safari, at: date(1)) == nil)
        }
    }

    @Test func specialCharactersRoundTrip() throws {
        try withStore { store, _ in
            let text = "It's 100% 'đúng' 🎉\n; DROP TABLE items;--"
            try store.add(.text(text), source: safari, at: date(1))
            try #expect(store.items().first?.text == text)
        }
    }

    @Test func filePathsRoundTrip() throws {
        try withStore { store, _ in
            try store.add(.files(["/a b/c.txt", "/d.png"]), source: safari, at: date(1))
            try #expect(store.items().first?.filePaths == ["/a b/c.txt", "/d.png"])
        }
    }

    @Test func missingSourceRoundTrips() throws {
        try withStore { store, _ in
            try store.add(.text("x"), source: ClipSource(), at: date(1))
            try #expect(store.items().first?.source == ClipSource())
        }
    }
}

@Suite struct ClipboardStoreImageTests {
    @Test func imageIsStoredAsBlob() throws {
        try withStore { store, directory in
            let item = try #require(try store.add(.image(imageA), source: safari, at: date(1)))
            let blobName = try #require(item.blobName)
            #expect(blobFiles(in: directory) == [blobName])
            #expect(store.imageData(for: item) == imageA)
            #expect(item.byteSize == imageA.count)
            #expect(item.text == "")
        }
    }

    @Test func oversizedImageIsRejected() throws {
        try withStore { store, directory in
            let tooBig = Data(count: 20_000_001)
            try #expect(store.add(.image(tooBig), source: safari, at: date(1)) == nil)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func missingBlobReturnsNil() throws {
        try withStore { store, directory in
            let item = try #require(try store.add(.image(imageA), source: safari, at: date(1)))
            let blobName = try #require(item.blobName)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("blobs/\(blobName)"))
            #expect(store.imageData(for: item) == nil)
        }
    }

    @Test func textItemHasNoImageData() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(.text("x"), source: safari, at: date(1)))
            #expect(store.imageData(for: item) == nil)
        }
    }
}

@Suite struct ClipboardStoreMutationTests {
    @Test func touchMovesItemToTop() throws {
        try withStore { store, _ in
            let a = try #require(try store.add(.text("a"), source: safari, at: date(1)))
            try store.add(.text("b"), source: safari, at: date(2))
            try store.touch(id: a.id, at: date(9))
            try #expect(store.items().map(\.text) == ["a", "b"])
        }
    }

    @Test func deleteRemovesItemAndBlob() throws {
        try withStore { store, directory in
            let item = try #require(try store.add(.image(imageA), source: safari, at: date(1)))
            try store.delete(id: item.id)
            try #expect(store.items().isEmpty)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func deleteAllRemovesEverything() throws {
        try withStore { store, directory in
            try store.add(.image(imageA), source: safari, at: date(1))
            try store.add(.text("a"), source: safari, at: date(2))
            try store.deleteAll()
            try #expect(store.items().isEmpty)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func pruneKeepsNewestUpToMaxItems() throws {
        try withStore(maxItems: 3) { store, _ in
            for index in 1...5 {
                try store.add(.text("item \(index)"), source: safari, at: date(Double(index)))
            }
            try #expect(store.items().map(\.text) == ["item 5", "item 4", "item 3"])
        }
    }

    @Test func pruneRemovesBlobs() throws {
        try withStore(maxItems: 1) { store, directory in
            try store.add(.image(imageA), source: safari, at: date(1))
            try store.add(.text("a"), source: safari, at: date(2))
            try #expect(store.items().map(\.kind) == [.text])
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func loweringMaxItemsPrunesImmediately() throws {
        try withStore { store, _ in
            for index in 1...5 {
                try store.add(.text("item \(index)"), source: safari, at: date(Double(index)))
            }
            try store.setMaxItems(2)
            #expect(store.maxItems == 2)
            try #expect(store.items().map(\.text) == ["item 5", "item 4"])
        }
    }

    @Test func prunedImageCanBeAddedAgain() throws {
        try withStore(maxItems: 1) { store, directory in
            try store.add(.image(imageA), source: safari, at: date(1))
            try store.add(.text("a"), source: safari, at: date(2))
            let again = try #require(try store.add(.image(imageA), source: safari, at: date(3)))
            #expect(store.imageData(for: again) == imageA)
            #expect(blobFiles(in: directory).count == 1)
        }
    }
}

@Suite struct ClipboardStorePersistenceTests {
    @Test func historySurvivesReopen() throws {
        try withDirectory { directory in
            do {
                let store = try ClipboardStore(directory: directory)
                try store.add(.text("first"), source: safari, at: date(1))
                try store.add(.image(imageA), source: notes, at: date(2))
            }
            let reopened = try ClipboardStore(directory: directory)
            let items = try reopened.items()
            #expect(items.map(\.kind) == [.image, .text])
            #expect(items[1].text == "first")
            #expect(reopened.imageData(for: items[0]) == imageA)
        }
    }

    @Test func createsMissingDirectory() throws {
        try withDirectory { directory in
            let nested = directory.appendingPathComponent("a/b")
            let store = try ClipboardStore(directory: nested)
            try store.add(.text("x"), source: safari, at: date(1))
            #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("clipboard.sqlite").path))
        }
    }

    @Test func newerSchemaIsRejected() throws {
        try withDirectory { directory in
            do { _ = try ClipboardStore(directory: directory) }

            var handle: OpaquePointer?
            let path = directory.appendingPathComponent("clipboard.sqlite").path
            #expect(sqlite3_open(path, &handle) == SQLITE_OK)
            #expect(sqlite3_exec(handle, "PRAGMA user_version = 99", nil, nil, nil) == SQLITE_OK)
            sqlite3_close(handle)

            #expect(throws: ClipboardStoreError.unsupportedSchema(version: 99)) {
                _ = try ClipboardStore(directory: directory)
            }
        }
    }
}
