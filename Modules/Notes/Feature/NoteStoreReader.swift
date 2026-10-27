import Foundation
import NotesCore
import os
import SQLite3

/// What `NotesStore` reads from Notes' database; `NoteStoreReader` is the real one, tests use a fake.
public protocol NoteDatabase: Sendable {
    var isReadable: Bool { get }
    func document(forNoteKey key: Int) -> DecodedNote?
    func attachmentFile(forAttachmentKey key: Int) -> URL?
}

/// Reads Apple Notes' own database, read only. It needs Full Disk Access; without it every call returns nil/false.
/// Each read opens the database and closes it again, so nothing stays locked while Notes is writing.
public final class NoteStoreReader: NoteDatabase {
    public static let defaultURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")

    private static let log = Logger(subsystem: "AraNotch", category: "Notes")
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let url: URL

    public init(url: URL = NoteStoreReader.defaultURL) { self.url = url }

    /// The folder that holds the database, the Accounts folders and the media.
    public var groupContainerURL: URL { url.deletingLastPathComponent() }

    /// True when the database opens and can really be read (a privacy denial often shows only at the first read).
    /// Computed on each access, since Full Disk Access may be granted while the app runs.
    public var isReadable: Bool {
        withDatabase { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT 1 FROM ZICCLOUDSYNCINGOBJECT LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return false }
            let step = sqlite3_step(statement)
            return step == SQLITE_ROW || step == SQLITE_DONE
        } ?? false
    }

    /// ZICNOTEDATA.ZDATA of a note, the gzip protobuf.
    public func rawData(forNoteKey key: Int) -> Data? {
        withDatabase { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT d.ZDATA FROM ZICCLOUDSYNCINGOBJECT n JOIN ZICNOTEDATA d ON d.Z_PK = n.ZNOTEDATA WHERE n.Z_PK = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int64(statement, 1, Int64(key))
            guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_BLOB else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            return Data(bytes: bytes, count: count)
        } ?? nil
    }

    /// The decoded note, or nil when it cannot be read or decoded.
    public func document(forNoteKey key: Int) -> DecodedNote? {
        guard let data = rawData(forNoteKey: key) else { return nil }
        do {
            return try NoteStoreDecoder.decode(data)
        } catch {
            Self.log.error("Could not decode note \(key, privacy: .public)")
            return nil
        }
    }

    // MARK: Attachment files

    /// The file of an image attachment, found through the database. nil without Full Disk Access or when not found.
    /// `key` is the Z_PK of the attachment row (from the AppleScript id …/ICAttachment/pNN).
    public func attachmentFile(forAttachmentKey key: Int) -> URL? {
        attachmentFile(whereClause: "a.Z_PK = ?") { sqlite3_bind_int64($0, 1, Int64(key)) }
    }

    /// `identifier` is the ZIDENTIFIER (UUID) of the attachment, as in the protobuf attachment info.
    public func attachmentFile(forIdentifier identifier: String) -> URL? {
        attachmentFile(whereClause: "a.ZIDENTIFIER = ?") { sqlite3_bind_text($0, 1, identifier, -1, Self.sqliteTransient) }
    }

    private func attachmentFile(whereClause: String, bind: (OpaquePointer?) -> Void) -> URL? {
        let row: (media: String, filename: String?, account: String?)? = withDatabase { db in
            let columns = Self.columns(of: "ZICCLOUDSYNCINGOBJECT", in: db)
            guard columns.contains("ZMEDIA"), columns.contains("ZIDENTIFIER") else { return nil }
            var accountParts: [String] = []
            for column in ["ZACCOUNT2", "ZACCOUNT"] where columns.contains(column) { accountParts.append("a.\(column)") }
            for column in ["ZACCOUNT2", "ZACCOUNT"] where columns.contains(column) { accountParts.append("m.\(column)") }
            let accountJoin = accountParts.isEmpty ? "" : "LEFT JOIN ZICCLOUDSYNCINGOBJECT acc ON acc.Z_PK = COALESCE(\(accountParts.joined(separator: ", ")))"
            let sql = "SELECT m.ZIDENTIFIER, \(columns.contains("ZFILENAME") ? "m.ZFILENAME" : "NULL"), \(accountParts.isEmpty ? "NULL" : "acc.ZIDENTIFIER") "
                + "FROM ZICCLOUDSYNCINGOBJECT a JOIN ZICCLOUDSYNCINGOBJECT m ON m.Z_PK = a.ZMEDIA \(accountJoin) WHERE \(whereClause)"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            bind(statement)
            guard sqlite3_step(statement) == SQLITE_ROW, let media = Self.text(statement, 0) else { return nil }
            return (media, Self.text(statement, 1), Self.text(statement, 2))
        } ?? nil
        guard let row, Self.isSafeComponent(row.media) else { return nil }

        let fileManager = FileManager.default
        var folders: [URL] = []
        let accounts = groupContainerURL.appendingPathComponent("Accounts")
        if let account = row.account, Self.isSafeComponent(account) {
            folders.append(accounts.appendingPathComponent("\(account)/Media/\(row.media)"))
        } else if let all = try? fileManager.contentsOfDirectory(atPath: accounts.path) {
            for account in all.sorted() { folders.append(accounts.appendingPathComponent("\(account)/Media/\(row.media)")) }
        }
        folders.append(groupContainerURL.appendingPathComponent("Media/\(row.media)"))
        let container = groupContainerURL.resolvingSymlinksInPath().path + "/"
        for folder in folders {
            let inside = Self.regularFiles(in: folder).filter { $0.resolvingSymlinksInPath().path.hasPrefix(container) }
            if let file = Self.choose(from: inside, preferring: row.filename) { return file }
        }
        return nil
    }

    private static func isSafeComponent(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\0") && name != ".." && name != "."
    }

    private static func regularFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// The file named `preferred`, else the first one.
    private static func choose(from files: [URL], preferring preferred: String?) -> URL? {
        if let preferred, let match = files.first(where: { $0.lastPathComponent == preferred }) { return match }
        return files.first
    }

    // MARK: SQLite

    private static func columns(of table: String, in db: OpaquePointer?) -> Set<String> {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return [] }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, 1) { names.insert(name) }
        }
        return names
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    /// Opens the database read only for the length of `body`, then closes it. nil when it cannot be opened.
    private func withDatabase<T>(_ body: (OpaquePointer?) -> T) -> T? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        return body(db)
    }
}
