import Foundation
import SQLite3
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-rich-tests-\(UUID().uuidString)")
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
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("blobs").path)) ?? [])
        .sorted()
}

private let rtf = Data(#"{\rtf1\ansi {\b Đậm}}"#.utf8)
private let html = Data("<b>Đậm</b>".utf8)
private let source = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")

@Suite struct ClipboardStoreRichTests {
    @Test func richTextIsStoredAndReturned() throws {
        try withStore { store, directory in
            let item = try #require(
                try store.add(.text("Đậm"), rich: ClipRichData(rtf: rtf, html: html), source: source, at: date(1)))
            #expect(item.hasRichData)
            #expect(store.richData(for: item) == ClipRichData(rtf: rtf, html: html))
            let files = blobFiles(in: directory)
            #expect(files.count == 2)
            #expect(files.contains { $0.hasSuffix(".rtf") })
            #expect(files.contains { $0.hasSuffix(".html") })
        }
    }

    @Test func plainTextHasNoRichData() throws {
        try withStore { store, directory in
            let item = try #require(try store.add(.text("thường"), source: source, at: date(1)))
            #expect(!item.hasRichData)
            #expect(store.richData(for: item) == nil)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func richDataIsIgnoredForImagesAndFiles() throws {
        try withStore { store, directory in
            let rich = ClipRichData(rtf: rtf, html: html)
            let image = try #require(try store.add(.image(Data([1, 2, 3])), rich: rich, source: source, at: date(1)))
            let file = try #require(try store.add(.files(["/tmp/a"]), rich: rich, source: source, at: date(2)))
            #expect(!image.hasRichData)
            #expect(!file.hasRichData)
            #expect(blobFiles(in: directory).count == 1)
        }
    }

    @Test func oversizedRichPartIsDropped() throws {
        try withStore { store, _ in
            let rich = ClipRichData(rtf: Data(count: 2_000_001), html: html)
            let item = try #require(try store.add(.text("x"), rich: rich, source: source, at: date(1)))
            #expect(store.richData(for: item) == ClipRichData(rtf: nil, html: html))
        }
    }

    @Test func emptyRichDataIsTreatedAsNone() throws {
        try withStore { store, directory in
            let item = try #require(
                try store.add(.text("x"), rich: ClipRichData(rtf: Data(), html: nil), source: source, at: date(1)))
            #expect(!item.hasRichData)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func duplicateReplacesRichData() throws {
        try withStore { store, _ in
            try store.add(.text("x"), rich: ClipRichData(rtf: rtf), source: source, at: date(1))
            let newer = Data(#"{\rtf1 mới}"#.utf8)
            let item = try #require(try store.add(.text("x"), rich: ClipRichData(rtf: newer), source: source, at: date(2)))
            #expect(store.richData(for: item) == ClipRichData(rtf: newer))
            #expect(try store.items().count == 1)
        }
    }

    @Test func duplicateWithoutRichRemovesOldRich() throws {
        try withStore { store, directory in
            try store.add(.text("x"), rich: ClipRichData(rtf: rtf, html: html), source: source, at: date(1))
            let item = try #require(try store.add(.text("x"), source: source, at: date(2)))
            #expect(!item.hasRichData)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func deleteRemovesRichBlobs() throws {
        try withStore { store, directory in
            let item = try #require(
                try store.add(.text("x"), rich: ClipRichData(rtf: rtf, html: html), source: source, at: date(1)))
            try store.delete(id: item.id)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func pruneRemovesRichBlobs() throws {
        try withStore(maxItems: 1) { store, directory in
            try store.add(.text("x"), rich: ClipRichData(rtf: rtf, html: html), source: source, at: date(1))
            try store.add(.text("y"), source: source, at: date(2))
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func missingRichBlobReturnsRemainingPart() throws {
        try withStore { store, directory in
            let item = try #require(
                try store.add(.text("x"), rich: ClipRichData(rtf: rtf, html: html), source: source, at: date(1)))
            let rtfName = try #require(item.rtfBlobName)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("blobs/\(rtfName)"))
            #expect(store.richData(for: item) == ClipRichData(rtf: nil, html: html))
        }
    }

    @Test func richDataSurvivesReopen() throws {
        try withDirectory { directory in
            do {
                let store = try ClipboardStore(directory: directory)
                try store.add(.text("x"), rich: ClipRichData(rtf: rtf), source: source, at: date(1))
            }
            let reopened = try ClipboardStore(directory: directory)
            let item = try #require(try reopened.items().first)
            #expect(reopened.richData(for: item) == ClipRichData(rtf: rtf))
        }
    }

    @Test func migratesVersion1Store() throws {
        try withDirectory { directory in
            // Build a store exactly as schema version 1 created it.
            let blobs = directory.appendingPathComponent("blobs")
            try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
            let image = Data([9, 8, 7])
            try image.write(to: blobs.appendingPathComponent("oldhash.png"))

            var handle: OpaquePointer?
            let path = directory.appendingPathComponent("clipboard.sqlite").path
            #expect(sqlite3_open(path, &handle) == SQLITE_OK)
            let sql = """
                CREATE TABLE items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, text TEXT NOT NULL,
                    blob_name TEXT, content_hash TEXT NOT NULL UNIQUE, source_bundle_id TEXT,
                    source_app_name TEXT, created_at REAL NOT NULL, last_used_at REAL NOT NULL,
                    byte_size INTEGER NOT NULL);
                CREATE INDEX items_last_used ON items (last_used_at);
                INSERT INTO items (kind, text, blob_name, content_hash, source_app_name, created_at, last_used_at, byte_size)
                    VALUES ('text', 'cũ', NULL, 'h1', 'Notes', 1, 1, 3);
                INSERT INTO items (kind, text, blob_name, content_hash, source_app_name, created_at, last_used_at, byte_size)
                    VALUES ('image', '', 'oldhash.png', 'h2', 'Safari', 2, 2, 3);
                PRAGMA user_version = 1;
                """
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(handle)

            let store = try ClipboardStore(directory: directory)
            let items = try store.items()
            #expect(items.map(\.kind) == [.image, .text])
            #expect(items[1].text == "cũ")
            #expect(!items[1].hasRichData)
            #expect(store.imageData(for: items[0]) == image)

            let added = try #require(try store.add(.text("mới"), rich: ClipRichData(rtf: rtf), source: source, at: date(3)))
            #expect(store.richData(for: added) == ClipRichData(rtf: rtf))

            #expect(sqlite3_open(path, &handle) == SQLITE_OK)
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int(statement, 0) == ClipboardStore.schemaVersion)
            sqlite3_finalize(statement)
            sqlite3_close(handle)
        }
    }
}
