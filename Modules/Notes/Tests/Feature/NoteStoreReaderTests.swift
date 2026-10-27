import Foundation
import SQLite3
import Testing
@testable import NotesFeature

/// A temporary group container with a NoteStore.sqlite shaped like Apple's, never the real one.
private final class TempStore {
    let directory: URL
    var dbURL: URL { directory.appendingPathComponent("NoteStore.sqlite") }

    init(objectColumns: [String] = ["Z_PK INTEGER PRIMARY KEY", "ZNOTEDATA INTEGER", "ZMEDIA INTEGER", "ZACCOUNT2 INTEGER",
                                    "ZACCOUNT INTEGER", "ZIDENTIFIER TEXT", "ZFILENAME TEXT"]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try exec("CREATE TABLE ZICCLOUDSYNCINGOBJECT (\(objectColumns.joined(separator: ", ")));"
                 + "CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZDATA BLOB);")
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func exec(_ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    }

    func insertNoteData(_ data: Data, noteKey: Int, dataKey: Int) throws {
        var db: OpaquePointer?
        sqlite3_open(dbURL.path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO ZICNOTEDATA (Z_PK, ZDATA) VALUES (?, ?)", -1, &statement, nil)
        sqlite3_bind_int(statement, 1, Int32(dataKey))
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), nil) }
        sqlite3_step(statement)
        sqlite3_finalize(statement)
        try exec("INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZNOTEDATA) VALUES (\(noteKey), \(dataKey))")
    }

    @discardableResult
    func makeFile(_ path: String, in root: URL? = nil) throws -> URL {
        let url = (root ?? directory).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("img".utf8).write(to: url)
        return url
    }
}

private func gzip(_ data: Data) throws -> Data {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("in.bin")
    try data.write(to: input)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.arguments = ["-c", input.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return output
}

/// document(2) > note(3) > note_text(2) = "Hi"
private let minimalProtobuf = Data([0x12, 0x06, 0x1a, 0x04, 0x12, 0x02, 0x48, 0x69])

@Suite struct NoteStoreReaderTests {
    @Test func readsNoteDataByKey() throws {
        let store = try TempStore()
        let payload = try gzip(minimalProtobuf)
        try store.insertNoteData(payload, noteKey: 96, dataKey: 7)
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.isReadable)
        #expect(reader.rawData(forNoteKey: 96) == payload)
        let decoded = reader.document(forNoteKey: 96)
        #expect(decoded?.document.blocks.count == 1)
    }

    @Test func readsTheRowsModificationDate() throws {
        let store = try TempStore(objectColumns: ["Z_PK INTEGER PRIMARY KEY", "ZNOTEDATA INTEGER", "ZMODIFICATIONDATE1 TIMESTAMP"])
        try store.insertNoteData(try gzip(minimalProtobuf), noteKey: 96, dataKey: 7)
        try store.exec("UPDATE ZICCLOUDSYNCINGOBJECT SET ZMODIFICATIONDATE1 = 800000000.5 WHERE Z_PK = 96")
        let note = NoteStoreReader(url: store.dbURL).note(forNoteKey: 96)
        #expect(note?.modified == Date(timeIntervalSinceReferenceDate: 800000000.5))
        #expect(note?.decoded.document.blocks.count == 1)
    }

    @Test func noDateColumnGivesNoDate() throws {
        let store = try TempStore()
        try store.insertNoteData(try gzip(minimalProtobuf), noteKey: 96, dataKey: 7)
        let note = NoteStoreReader(url: store.dbURL).note(forNoteKey: 96)
        #expect(note != nil)
        #expect(note?.modified == nil)
    }

    /// The row key of each attachment of the note, found by the identifier its data names, in document order.
    @Test func findsTheRowKeyOfEachAttachment() throws {
        // Protobuf by hand (fields below 16, lengths below 128): a tag byte, then a varint or a length and bytes.
        func bytes(_ field: UInt8, _ data: Data) -> Data { Data([field << 3 | 2, UInt8(data.count)]) + data }
        func varint(_ field: UInt8, _ value: UInt8) -> Data { Data([field << 3, value]) }
        var note = bytes(2, Data("\u{FFFC}\n\u{FFFC}".utf8))
        for (length, identifier) in [(UInt8(2), "SECOND-ADDED"), (1, "MISSING")] {
            let info = bytes(1, Data(identifier.utf8)) + bytes(2, Data("public.png".utf8))
            note += bytes(5, varint(1, length) + bytes(12, info))
        }
        let protobuf = bytes(2, bytes(3, note))
        let store = try TempStore()
        try store.insertNoteData(try gzip(protobuf), noteKey: 96, dataKey: 7)
        try store.exec("INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER) VALUES (40, 'SECOND-ADDED')")
        #expect(NoteStoreReader(url: store.dbURL).note(forNoteKey: 96)?.attachmentKeys == [40, nil])
    }

    /// A picture Notes got through HTML is "public.data" in a file with no extension: its bytes make it a picture.
    @Test func publicDataWhoseFileIsAPictureIsAPicture() throws {
        func bytes(_ field: UInt8, _ data: Data) -> Data { Data([field << 3 | 2, UInt8(data.count)]) + data }
        func varint(_ field: UInt8, _ value: UInt8) -> Data { Data([field << 3, value]) }
        var note = bytes(2, Data("\u{FFFC}\n\u{FFFC}".utf8))
        for (length, identifier) in [(UInt8(2), "PICTURE"), (1, "TEXT")] {
            let info = bytes(1, Data(identifier.utf8)) + bytes(2, Data("public.data".utf8))
            note += bytes(5, varint(1, length) + bytes(12, info))
        }
        let store = try TempStore()
        try store.insertNoteData(try gzip(bytes(2, bytes(3, note))), noteKey: 96, dataKey: 7)
        try store.exec("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER) VALUES (5, 'ACC');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFILENAME) VALUES (21, 'M1', 'M1');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFILENAME) VALUES (23, 'M2', 'M2');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZMEDIA, ZACCOUNT2) VALUES (20, 'PICTURE', 21, 5);
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZMEDIA, ZACCOUNT2) VALUES (22, 'TEXT', 23, 5);
            """)
        let png = try store.makeFile("Accounts/ACC/Media/M1/M1")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]).write(to: png)
        try store.makeFile("Accounts/ACC/Media/M2/M2")
        let blocks = NoteStoreReader(url: store.dbURL).note(forNoteKey: 96)?.decoded.document.blocks
        #expect(blocks == [.image(attachmentIndex: 0), .file(attachmentIndex: 1, name: "", uti: "public.data")])
        // A real file keeps its name: a raw photo is TIFF inside, but it stays a file.
        try store.exec("UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILENAME = 'photo.dng' WHERE Z_PK = 21")
        try FileManager.default.removeItem(at: png)
        try Data([0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 0]).write(to: try store.makeFile("Accounts/ACC/Media/M1/photo.dng"))
        let raw = NoteStoreReader(url: store.dbURL).note(forNoteKey: 96)?.decoded.document.blocks.first
        #expect(raw == .file(attachmentIndex: 0, name: "", uti: "public.data"))
    }

    @Test func missingKeyIsNil() throws {
        let store = try TempStore()
        try store.insertNoteData(try gzip(minimalProtobuf), noteKey: 1, dataKey: 1)
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.rawData(forNoteKey: 2) == nil)
        #expect(reader.document(forNoteKey: 2) == nil)
    }

    @Test func unreadableFileIsNotReadable() {
        let reader = NoteStoreReader(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/NoteStore.sqlite"))
        #expect(!reader.isReadable)
        #expect(reader.rawData(forNoteKey: 1) == nil)
    }

    @Test func corruptDataIsNil() throws {
        let store = try TempStore()
        try store.insertNoteData(Data("not gzip".utf8), noteKey: 3, dataKey: 3)
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.rawData(forNoteKey: 3) != nil)
        #expect(reader.document(forNoteKey: 3) == nil)
    }

    // MARK: Attachment files

    private func addImage(_ store: TempStore, attachment: Int = 20, media: Int = 21, account: Int = 5,
                          mediaID: String = "MEDIA-UUID", accountID: String = "ACC-UUID", filename: String = "pic.jpg",
                          attachmentID: String = "ATT-UUID", accountColumn: String = "ZACCOUNT2") throws {
        try store.exec("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER) VALUES (\(account), '\(accountID)');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFILENAME) VALUES (\(media), '\(mediaID)', '\(filename)');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZMEDIA, \(accountColumn)) VALUES (\(attachment), '\(attachmentID)', \(media), \(account));
            """)
    }

    @Test func attachmentFoundByKey() throws {
        let store = try TempStore()
        try addImage(store)
        let file = try store.makeFile("Accounts/ACC-UUID/Media/MEDIA-UUID/pic.jpg")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.groupContainerURL.standardizedFileURL == store.directory.standardizedFileURL)
        #expect(reader.attachmentFile(forAttachmentKey: 20)?.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test func attachmentFoundByIdentifier() throws {
        let store = try TempStore()
        try addImage(store)
        let file = try store.makeFile("Accounts/ACC-UUID/Media/MEDIA-UUID/pic.jpg")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.attachmentFile(forIdentifier: "ATT-UUID")?.standardizedFileURL.path == file.standardizedFileURL.path)
        #expect(reader.attachmentFile(forIdentifier: "nope") == nil)
    }

    @Test func attachmentWithoutMediaIsNil() throws {
        let store = try TempStore()
        try store.exec("INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER) VALUES (30, 'X')")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.attachmentFile(forAttachmentKey: 30) == nil)
        #expect(reader.attachmentFile(forAttachmentKey: 999) == nil)
    }

    @Test func attachmentWorksWithoutAccount2Column() throws {
        let store = try TempStore(objectColumns: ["Z_PK INTEGER PRIMARY KEY", "ZNOTEDATA INTEGER", "ZMEDIA INTEGER",
                                                  "ZACCOUNT INTEGER", "ZIDENTIFIER TEXT", "ZFILENAME TEXT"])
        try addImage(store, accountColumn: "ZACCOUNT")
        let file = try store.makeFile("Accounts/ACC-UUID/Media/MEDIA-UUID/pic.jpg")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.attachmentFile(forAttachmentKey: 20)?.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test func attachmentInGenerationSubfolder() throws {
        let store = try TempStore()
        try addImage(store, filename: "photo.png")
        let file = try store.makeFile("Accounts/ACC-UUID/Media/MEDIA-UUID/1_OTHER-UUID/photo.png")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.attachmentFile(forAttachmentKey: 20)?.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test func attachmentFallsBackToRootMediaFolder() throws {
        let store = try TempStore()
        try addImage(store)
        let file = try store.makeFile("Media/MEDIA-UUID/1_X/pic.jpg")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.attachmentFile(forAttachmentKey: 20)?.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test func attachmentSearchesAllAccountsWhenAccountUnknown() throws {
        let store = try TempStore()
        try store.exec("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFILENAME) VALUES (21, 'MEDIA-UUID', 'pic.jpg');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZMEDIA) VALUES (20, 'ATT-UUID', 21);
            """)
        let file = try store.makeFile("Accounts/SOME-ACCOUNT/Media/MEDIA-UUID/pic.jpg")
        let reader = NoteStoreReader(url: store.dbURL)
        #expect(reader.attachmentFile(forAttachmentKey: 20)?.standardizedFileURL.path == file.standardizedFileURL.path)
    }

    @Test func symlinkLeavingTheContainerIsRejected() throws {
        let store = try TempStore()
        try addImage(store)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let folder = store.directory.appendingPathComponent("Accounts/ACC-UUID/Media/MEDIA-UUID")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("pic.jpg"), withDestinationURL: outside)
        #expect(NoteStoreReader(url: store.dbURL).attachmentFile(forAttachmentKey: 20) == nil)
    }

    @Test func traversalInIdentifiersAndFilenamesDoesNotEscape() throws {
        let store = try TempStore()
        try addImage(store, mediaID: "../Secret")
        try store.makeFile("Secret/leak.jpg")
        #expect(NoteStoreReader(url: store.dbURL).attachmentFile(forAttachmentKey: 20) == nil)

        let other = try TempStore()
        try addImage(other, accountID: "../..", filename: "../../leak.jpg")
        try other.makeFile("Media/MEDIA-UUID/../../leak.jpg")
        #expect(NoteStoreReader(url: other.dbURL).attachmentFile(forAttachmentKey: 20) == nil)
        let sibling = try TempStore()
        try addImage(sibling, filename: "../../../leak.jpg")
        #expect(NoteStoreReader(url: sibling.dbURL).attachmentFile(forAttachmentKey: 20) == nil)
    }

    @Test func missingFileIsNil() throws {
        let store = try TempStore()
        try addImage(store)
        #expect(NoteStoreReader(url: store.dbURL).attachmentFile(forAttachmentKey: 20) == nil)
    }
}

@Suite struct NoteStoreWatcherTests {
    @MainActor @Test func coalescesChangesWithinTheInterval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("NoteStore.sqlite")
        try Data("a".utf8).write(to: file)
        final class Counter: @unchecked Sendable { var count = 0 }
        let counter = Counter()
        let watcher = NoteStoreWatcher(url: file, coalescing: 0.5) { counter.count += 1 }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<2 {
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("b".utf8))
            try handle.close()
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(1300))
        #expect(counter.count == 1)
    }
}
