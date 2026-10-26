import Foundation
import SQLite3
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-link-tests-\(UUID().uuidString)")
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

private let link = ClipContent.text("https://example.com/bai-viet")
private let picture = Data([0xFF, 0xD8, 0xFF, 1, 2, 3])
private let source = ClipSource(bundleID: "com.apple.Safari", appName: "Safari")

@Suite struct ClipboardStoreLinkTests {
    @Test func newLinkHasNoPreview() throws {
        try withStore { store, _ in
            let item = try #require(try store.add(link, source: source, at: date(1)))
            #expect(item.kind == .link)
            #expect(item.linkTitle == nil)
            #expect(item.linkImageBlobName == nil)
            #expect(item.linkCheckedAt == nil)
            #expect(store.linkImageData(for: item) == nil)
        }
    }

    @Test func setLinkPreviewStoresTitleAndImage() throws {
        try withStore { store, directory in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: "Bài viết", imageData: picture, at: date(5))

            let item = try #require(try store.item(id: added.id))
            #expect(item.linkTitle == "Bài viết")
            #expect(item.linkCheckedAt == date(5))
            #expect(store.linkImageData(for: item) == picture)
            #expect(blobFiles(in: directory).filter { $0.hasSuffix(".preview") }.count == 1)
        }
    }

    @Test func emptyResultStillMarksChecked() throws {
        try withStore { store, directory in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: nil, imageData: nil, at: date(5))
            let item = try #require(try store.item(id: added.id))
            #expect(item.linkTitle == nil)
            #expect(item.linkImageBlobName == nil)
            #expect(item.linkCheckedAt == date(5))
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func oversizedLinkImageIsDropped() throws {
        try withStore { store, directory in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: "T", imageData: Data(count: 2_000_001), at: date(5))
            let item = try #require(try store.item(id: added.id))
            #expect(item.linkTitle == "T")
            #expect(item.linkImageBlobName == nil)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func recopyingKeepsThePreview() throws {
        try withStore { store, _ in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: "Bài viết", imageData: picture, at: date(5))
            let again = try #require(try store.add(link, source: source, at: date(9)))
            #expect(again.id == added.id)
            #expect(again.linkTitle == "Bài viết")
            #expect(again.linkCheckedAt == date(5))
            #expect(store.linkImageData(for: again) == picture)
        }
    }

    @Test func deleteRemovesPreviewBlob() throws {
        try withStore { store, directory in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: "T", imageData: picture, at: date(5))
            try store.delete(id: added.id)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func pruneRemovesPreviewBlob() throws {
        try withStore(maxItems: 1) { store, directory in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: "T", imageData: picture, at: date(5))
            try store.add(.text("khác"), source: source, at: date(6))
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func deleteAllRemovesPreviewBlob() throws {
        try withStore { store, directory in
            let added = try #require(try store.add(link, source: source, at: date(1)))
            try store.setLinkPreview(id: added.id, title: "T", imageData: picture, at: date(5))
            try store.deleteAll()
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func setLinkPreviewOnMissingItemDoesNothing() throws {
        try withStore { store, directory in
            try store.setLinkPreview(id: 999, title: "T", imageData: picture, at: date(5))
            #expect(try store.items().isEmpty)
            #expect(blobFiles(in: directory).isEmpty)
        }
    }

    @Test func previewSurvivesReopen() throws {
        try withDirectory { directory in
            do {
                let store = try ClipboardStore(directory: directory)
                let added = try #require(try store.add(link, source: source, at: date(1)))
                try store.setLinkPreview(id: added.id, title: "Bài viết", imageData: picture, at: date(5))
            }
            let reopened = try ClipboardStore(directory: directory)
            let item = try #require(try reopened.items().first)
            #expect(item.linkTitle == "Bài viết")
            #expect(reopened.linkImageData(for: item) == picture)
        }
    }

    @Test func migratesVersion2Store() throws {
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
                    byte_size INTEGER NOT NULL, rtf_blob TEXT, html_blob TEXT);
                INSERT INTO items (kind, text, content_hash, source_app_name, created_at, last_used_at, byte_size)
                    VALUES ('link', 'https://example.com/cu', 'h1', 'Safari', 1, 1, 22);
                PRAGMA user_version = 2;
                """
            #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(handle)

            let store = try ClipboardStore(directory: directory)
            let item = try #require(try store.items().first)
            #expect(item.text == "https://example.com/cu")
            #expect(item.linkCheckedAt == nil)
            try store.setLinkPreview(id: item.id, title: "Cũ", imageData: nil, at: date(3))
            #expect(try store.item(id: item.id)?.linkTitle == "Cũ")

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
