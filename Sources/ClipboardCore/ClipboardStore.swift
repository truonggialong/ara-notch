import CryptoKit
import Foundation

public enum ClipboardStoreError: Error, Equatable {
    case cannotOpen(String)
    /// The file was written by a newer version of the app.
    case unsupportedSchema(version: Int)
    case sqlite(String)
    /// The history file is damaged: SQLite cannot read it, or finds it inconsistent.
    case damaged(String)
    /// The board name is empty or too long.
    case invalidBoardName
    case duplicateBoardName
    case tooManyBoards
    case boardFull
    /// The operation needs the vault to be unlocked.
    case vaultLocked
    case wrongPasscode
    /// The passcode is too short.
    case invalidPasscode
    case vaultAlreadyExists
    case vaultNotSetUp
}

/// The clipboard history: rows in `clipboard.sqlite`, image data as files in `blobs/`.
public final class ClipboardStore {
    public static let schemaVersion = 6
    public static let maxTextBytes = 1_000_000
    public static let maxImageBytes = 20_000_000

    /// Whether the content is over the size the history keeps, so the user can be told.
    public static func isTooLarge(_ content: ClipContent) -> Bool {
        switch content {
        case .text(let string): string.utf8.count > maxTextBytes
        case .image(let data): data.count > maxImageBytes
        case .files: false
        }
    }
    /// Limit for each of the RTF and HTML versions; a larger one is dropped, the text is kept.
    public static let maxRichBytes = 2_000_000
    public static let maxLinkImageBytes = 2_000_000

    static let columns = """
        id, kind, text, blob_name, source_bundle_id, source_app_name, created_at, last_used_at, byte_size,
        rtf_blob, html_blob, link_title, link_image_blob, link_checked_at, is_encrypted, title, ocr_text
        """
    static let blobColumns = "blob_name, rtf_blob, html_blob, link_image_blob"
    static let newestFirst = "ORDER BY last_used_at DESC, id DESC"

    public private(set) var maxItems: Int
    /// Whether newly stored text of six or eight hex digits without `#` counts as a colour.
    public var recognisesBareHexColors = false

    let database: SQLiteDatabase
    private let blobDirectory: URL
    /// The vault's data key; present only while the vault is unlocked. Never written to disk.
    var vaultKey: VaultKey?

    /// - Parameter inMemory: keeps the database in memory (for tests); images still go to `directory`.
    public init(directory: URL, inMemory: Bool = false, maxItems: Int = 500) throws {
        self.maxItems = max(1, maxItems)
        blobDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        } catch {
            throw ClipboardStoreError.cannotOpen(error.localizedDescription)
        }
        let path = inMemory ? ":memory:" : directory.appendingPathComponent("clipboard.sqlite").path
        database = try SQLiteDatabase(path: path)
        // Deleted rows are overwritten, so content moved into the vault does not linger in free pages.
        try database.execute("PRAGMA secure_delete = ON")
        try migrate()
    }

    /// Opens an existing history for reading only: nothing is created, upgraded or written, and
    /// the vault stays locked. Fails when there is no history yet or it has another schema version.
    public init(readingFrom directory: URL) throws {
        maxItems = .max
        blobDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        let path = directory.appendingPathComponent("clipboard.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else {
            throw ClipboardStoreError.cannotOpen("no clipboard history at \(path)")
        }
        database = try SQLiteDatabase(path: path, readOnly: true)
        let version = try database.userVersion
        guard version == Self.schemaVersion else {
            throw ClipboardStoreError.unsupportedSchema(version: version)
        }
    }

    private func migrate() throws {
        let version = try database.userVersion
        guard version <= Self.schemaVersion else {
            throw ClipboardStoreError.unsupportedSchema(version: version)
        }
        if version == 0 {
            try createSchema()
        } else {
            // Upgrade one version at a time.
            if version < 2 {
                // Version 2 added the rich-text columns.
                try database.execute("ALTER TABLE items ADD COLUMN rtf_blob TEXT")
                try database.execute("ALTER TABLE items ADD COLUMN html_blob TEXT")
            }
            if version < 3 {
                // Version 3 added link previews.
                try database.execute("ALTER TABLE items ADD COLUMN link_title TEXT")
                try database.execute("ALTER TABLE items ADD COLUMN link_image_blob TEXT")
                try database.execute("ALTER TABLE items ADD COLUMN link_checked_at REAL")
            }
            if version < 5 {
                // Version 5 added the vault: encrypted clips and locked boards.
                try database.execute("ALTER TABLE items ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0")
            }
            if version < 6 {
                // Version 6 added the user's title for a clip and the text read from an image.
                try database.execute("ALTER TABLE items ADD COLUMN title TEXT")
                try database.execute("ALTER TABLE items ADD COLUMN ocr_text TEXT")
            }
            if version == 4 {
                // Boards exist since version 4; older stores get the column when the table is created below.
                try database.execute("ALTER TABLE boards ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0")
            }
        }
        // Version 4 added boards and version 5 the vault; creating them is harmless on a fresh store too.
        try createBoardTables()
        try createVaultTable()
        try database.setUserVersion(Self.schemaVersion)
    }

    private func createSchema() throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT NOT NULL,
                blob_name TEXT,
                content_hash TEXT NOT NULL UNIQUE,
                source_bundle_id TEXT,
                source_app_name TEXT,
                created_at REAL NOT NULL,
                last_used_at REAL NOT NULL,
                byte_size INTEGER NOT NULL,
                rtf_blob TEXT,
                html_blob TEXT,
                link_title TEXT,
                link_image_blob TEXT,
                link_checked_at REAL,
                is_encrypted INTEGER NOT NULL DEFAULT 0,
                title TEXT,
                ocr_text TEXT
            )
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS items_last_used ON items (last_used_at)")
    }

    // MARK: - Writing

    public func setMaxItems(_ value: Int) throws {
        maxItems = max(1, value)
        try prune()
    }

    /// Stores the content, or moves the existing entry to the top when the same content is copied
    /// again. Returns nil when the content is empty or too large to keep.
    @discardableResult
    public func add(_ content: ClipContent, source: ClipSource, at date: Date) throws -> ClipItem? {
        try add(content, rich: nil, source: source, at: date)
    }

    /// - Parameter rich: formatted versions of a text clip; ignored for images and files.
    @discardableResult
    public func add(
        _ content: ClipContent, rich: ClipRichData?, source: ClipSource, at date: Date
    ) throws -> ClipItem? {
        guard let stored = try insert(content, rich: rich, source: source, at: date) else { return nil }
        return try item(id: stored.id)
    }

    /// Stores the content and says whether a new entry was made. Nil when the content cannot be kept.
    /// - Parameters:
    ///   - createdAt: creation date of a new entry; defaults to `date`.
    ///   - keepingDuplicate: leave an entry with the same content exactly as it is, instead of
    ///     moving it to the top.
    ///   - pruning: apply the history limit afterwards.
    func insert(
        _ content: ClipContent, rich: ClipRichData?, source: ClipSource, at date: Date,
        createdAt: Date? = nil, keepingDuplicate: Bool = false, pruning: Bool = true
    ) throws -> (id: Int64, isNew: Bool)? {
        let kind = ClipClassifier.kind(of: content, allowingBareHex: recognisesBareHexColors)
        var isText = false
        let text: String
        let payload: Data
        var imageData: Data?

        switch content {
        case .text(let string):
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  string.utf8.count <= Self.maxTextBytes
            else { return nil }
            text = string
            payload = Data(string.utf8)
            isText = true
        case .image(let data):
            guard !data.isEmpty, data.count <= Self.maxImageBytes else { return nil }
            text = ""
            payload = data
            imageData = data
        case .files(let paths):
            guard !paths.isEmpty else { return nil }
            text = paths.joined(separator: "\n")
            payload = Data(text.utf8)
        }

        let hash = Self.hash(kind: kind, payload: payload)
        let timestamp = date.timeIntervalSince1970
        let blobName = imageData.map { "\(hash).\(ClipImageData.fileExtension(of: $0))" }
        let rtf = isText ? Self.usableRichPart(rich?.rtf) : nil
        let html = isText ? Self.usableRichPart(rich?.html) : nil
        let rtfName = rtf == nil ? nil : "\(hash).rtf"
        let htmlName = html == nil ? nil : "\(hash).html"

        if let existingID = try database.query("SELECT id FROM items WHERE content_hash = ?", [.text(hash)])
            .first?.first?.int64 {
            if keepingDuplicate {
                return (existingID, false)
            }
            // Same content copied again: restore a lost image file, then move the entry to the top.
            if let imageData, let blobName, !FileManager.default.fileExists(atPath: blobURL(blobName).path) {
                try? imageData.write(to: blobURL(blobName), options: .atomic)
            }
            // The formatting of the latest copy replaces whatever was stored before.
            try writeRichPart(rtf, named: "\(hash).rtf")
            try writeRichPart(html, named: "\(hash).html")
            try database.execute(
                """
                UPDATE items SET last_used_at = ?, source_bundle_id = ?, source_app_name = ?,
                                 rtf_blob = ?, html_blob = ?
                WHERE id = ?
                """,
                [
                    .real(timestamp), Self.optional(source.bundleID), Self.optional(source.appName),
                    Self.optional(rtfName), Self.optional(htmlName), .integer(existingID),
                ])
            return (existingID, false)
        }

        // Write the image before the row, so a row never points at a file that was not written.
        if let imageData, let blobName {
            do {
                try imageData.write(to: blobURL(blobName), options: .atomic)
            } catch {
                throw ClipboardStoreError.sqlite("cannot write image: \(error.localizedDescription)")
            }
        }
        do {
            try writeRichPart(rtf, named: "\(hash).rtf")
            try writeRichPart(html, named: "\(hash).html")
            try database.execute(
                """
                INSERT INTO items (kind, text, blob_name, content_hash, source_bundle_id, source_app_name,
                                   created_at, last_used_at, byte_size, rtf_blob, html_blob)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(kind.rawValue), .text(text), Self.optional(blobName), .text(hash),
                    Self.optional(source.bundleID), Self.optional(source.appName),
                    .real((createdAt ?? date).timeIntervalSince1970), .real(timestamp), .integer(Int64(payload.count)),
                    Self.optional(rtfName), Self.optional(htmlName),
                ])
        } catch {
            [blobName, rtfName, htmlName].compactMap { $0 }.forEach(removeBlob)
            throw error
        }

        let id = database.lastInsertRowID
        if pruning {
            try prune()
        }
        return (id, true)
    }

    public func touch(id: Int64, at date: Date) throws {
        try database.execute(
            "UPDATE items SET last_used_at = ? WHERE id = ?", [.real(date.timeIntervalSince1970), .integer(id)])
    }

    /// Records the outcome of a preview fetch for a link. An empty outcome is recorded too, so
    /// the link is not fetched again. Does nothing when the item no longer exists.
    public func setLinkPreview(id: Int64, title: String?, imageData: Data?, at date: Date) throws {
        guard let hash = try database.query("SELECT content_hash FROM items WHERE id = ?", [.integer(id)])
            .first?.first?.string
        else { return }

        var imageName: String?
        if let imageData, !imageData.isEmpty, imageData.count <= Self.maxLinkImageBytes {
            let name = "\(hash).preview"
            if (try? imageData.write(to: blobURL(name), options: .atomic)) != nil {
                imageName = name
            }
        }
        try database.execute(
            "UPDATE items SET link_title = ?, link_image_blob = ?, link_checked_at = ? WHERE id = ?",
            [Self.optional(title), Self.optional(imageName), .real(date.timeIntervalSince1970), .integer(id)])
    }

    /// Gives the clip a name, or takes it away when the name is empty.
    public func setTitle(id: Int64, title: String?) throws {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try database.execute(
            "UPDATE items SET title = ? WHERE id = ?", [trimmed.isEmpty ? .null : .text(trimmed), .integer(id)])
    }

    /// Changes the text of a text, link or colour clip. The clip keeps its place on boards, its
    /// title and its creation date; formatted versions and a link preview belonged to the old
    /// text and are dropped. The edit counts as a use, so the clip moves to the top.
    public func updateText(id: Int64, text newText: String, at date: Date) throws -> ClipTextUpdate {
        let query = "SELECT kind, text, is_encrypted, rtf_blob, html_blob, link_image_blob FROM items WHERE id = ?"
        guard let row = try database.query(query, [.integer(id)]).first,
              let kind = row[0].string.flatMap(ClipKind.init(rawValue:)), let oldText = row[1].string,
              kind == .text || kind == .link || kind == .color, row[2].int64 != 1,
              !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              newText.utf8.count <= Self.maxTextBytes
        else { return .notEditable }
        guard newText != oldText else { return .unchanged }

        let newKind = ClipClassifier.kind(of: .text(newText), allowingBareHex: recognisesBareHexColors)
        let hash = Self.hash(kind: newKind, payload: Data(newText.utf8))
        let other = try database.query(
            "SELECT id FROM items WHERE content_hash = ? AND id != ?", [.text(hash), .integer(id)])
        guard other.isEmpty else { return .duplicate }

        try database.execute(
            """
            UPDATE items SET kind = ?, text = ?, content_hash = ?, byte_size = ?, last_used_at = ?,
                             rtf_blob = NULL, html_blob = NULL,
                             link_title = NULL, link_image_blob = NULL, link_checked_at = NULL
            WHERE id = ?
            """,
            [
                .text(newKind.rawValue), .text(newText), .text(hash), .integer(Int64(newText.utf8.count)),
                .real(date.timeIntervalSince1970), .integer(id),
            ])
        [row[3].string, row[4].string, row[5].string].compactMap { $0 }.forEach(removeBlob)
        return .updated
    }

    /// Keeps the text read from an image clip. Empty text is kept too: it says the image was
    /// read and holds none, so it is not read again.
    public func setRecognizedText(id: Int64, text: String) throws {
        try database.execute("UPDATE items SET ocr_text = ? WHERE id = ?", [.text(text), .integer(id)])
    }

    /// Image clips whose text was not read yet, newest first. Vault clips are left alone.
    public func imagesAwaitingRecognition(limit: Int) throws -> [ClipItem] {
        try database.query(
            """
            SELECT \(Self.columns) FROM items
            WHERE kind = 'image' AND ocr_text IS NULL AND is_encrypted = 0 \(Self.newestFirst) LIMIT ?
            """,
            [.integer(Int64(limit))]).compactMap(Self.makeItem)
    }

    /// Deletes the clip, pinned or not, and removes it from every board.
    public func delete(id: Int64) throws {
        let blobs = try database.query("SELECT \(Self.blobColumns) FROM items WHERE id = ?", [.integer(id)])
        try database.execute("DELETE FROM board_items WHERE item_id = ?", [.integer(id)])
        try database.execute("DELETE FROM items WHERE id = ?", [.integer(id)])
        blobs.flatMap { $0 }.compactMap(\.string).forEach(removeBlob)
    }

    /// Clears the history. Pinned clips and the boards themselves are kept.
    public func deleteAll() throws {
        let blobs = try database.query("SELECT \(Self.blobColumns) FROM items WHERE \(Self.isUnpinned)")
        try database.execute("DELETE FROM items WHERE \(Self.isUnpinned)")
        blobs.flatMap { $0 }.compactMap(\.string).forEach(removeBlob)
    }

    /// Deletes unpinned clips last used before `cutoff`, with their files. Returns how many.
    @discardableResult
    public func deleteUnpinned(olderThan cutoff: Date) throws -> Int {
        let expired = "\(Self.isUnpinned) AND last_used_at < ?"
        let bound: [SQLiteValue] = [.real(cutoff.timeIntervalSince1970)]
        let rows = try database.query("SELECT \(Self.blobColumns) FROM items WHERE \(expired)", bound)
        guard !rows.isEmpty else { return 0 }
        try database.execute("DELETE FROM items WHERE \(expired)", bound)
        rows.flatMap { $0 }.compactMap(\.string).forEach(removeBlob)
        return rows.count
    }

    /// Deletes unpinned clips last used at or after `start`, with their files. Returns how many.
    /// For taking back what was copied in the last while.
    @discardableResult
    public func deleteUnpinned(usedSince start: Date) throws -> Int {
        let recent = "\(Self.isUnpinned) AND last_used_at >= ?"
        let bound: [SQLiteValue] = [.real(start.timeIntervalSince1970)]
        let rows = try database.query("SELECT \(Self.blobColumns) FROM items WHERE \(recent)", bound)
        guard !rows.isEmpty else { return 0 }
        try database.execute("DELETE FROM items WHERE \(recent)", bound)
        rows.flatMap { $0 }.compactMap(\.string).forEach(removeBlob)
        return rows.count
    }

    // MARK: - Reading

    /// The history, newest first. Vault clips are never part of it, locked or not.
    public func items() throws -> [ClipItem] {
        try database.query("SELECT \(Self.columns) FROM items WHERE is_encrypted = 0 \(Self.newestFirst)")
            .compactMap(Self.makeItem)
    }

    public func linkImageData(for item: ClipItem) -> Data? {
        readBlob(item.linkImageBlobName, of: item)
    }

    public func imageData(for item: ClipItem) -> Data? {
        readBlob(item.blobName, of: item)
    }

    /// The file an image clip is kept in, for opening it in another app. Nil for vault clips,
    /// whose files are encrypted.
    public func imageFileURL(for item: ClipItem) -> URL? {
        guard item.kind == .image, !item.isEncrypted, let name = item.blobName else { return nil }
        return blobURL(name)
    }

    /// A clip's file. For a vault clip the file is decrypted, which needs the vault unlocked.
    private func readBlob(_ name: String?, of item: ClipItem) -> Data? {
        guard let name, let data = try? Data(contentsOf: blobURL(name)) else { return nil }
        guard item.isEncrypted else { return data }
        guard let vaultKey else { return nil }
        return try? VaultCrypto.open(data, with: vaultKey)
    }

    /// The stored formatted versions, or nil when the clip has none. A version whose file is
    /// missing is simply absent from the result.
    public func richData(for item: ClipItem) -> ClipRichData? {
        guard item.hasRichData else { return nil }
        let rich = ClipRichData(
            rtf: readBlob(item.rtfBlobName, of: item),
            html: readBlob(item.htmlBlobName, of: item))
        return rich.isEmpty ? nil : rich
    }

    // MARK: - Helpers

    /// Empty or oversized parts are not kept.
    private static func usableRichPart(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty, data.count <= maxRichBytes else { return nil }
        return data
    }

    /// Writes the part, or removes a previously stored file when there is none now.
    private func writeRichPart(_ data: Data?, named name: String) throws {
        guard let data else {
            removeBlob(name)
            return
        }
        do {
            try data.write(to: blobURL(name), options: .atomic)
        } catch {
            throw ClipboardStoreError.sqlite("cannot write rich text: \(error.localizedDescription)")
        }
    }

    /// The clip with this id; nil when it does not exist, or is in the vault while the vault is locked.
    public func item(id: Int64) throws -> ClipItem? {
        guard let stored = try storedItem(id: id) else { return nil }
        return stored.isEncrypted ? try? decrypted(stored) : stored
    }

    /// The row as stored: for a vault clip the text is still ciphertext.
    func storedItem(id: Int64) throws -> ClipItem? {
        try database.query("SELECT \(Self.columns) FROM items WHERE id = ?", [.integer(id)])
            .first.flatMap(Self.makeItem)
    }

    /// Matches clips that are on no board.
    static let isUnpinned = "id NOT IN (SELECT item_id FROM board_items)"

    /// Deletes the oldest unpinned entries beyond `maxItems`, together with their files.
    /// Pinned clips do not count towards the limit and are never pruned.
    func prune() throws {
        let surplus = try database.query(
            "SELECT id, \(Self.blobColumns) FROM items WHERE \(Self.isUnpinned) \(Self.newestFirst) LIMIT -1 OFFSET ?",
            [.integer(Int64(maxItems))])
        for row in surplus {
            guard let id = row[0].int64 else { continue }
            try database.execute("DELETE FROM items WHERE id = ?", [.integer(id)])
            row.dropFirst().compactMap(\.string).forEach(removeBlob)
        }
    }

    func blobURL(_ name: String) -> URL {
        blobDirectory.appendingPathComponent(name)
    }

    func removeBlob(_ name: String) {
        try? FileManager.default.removeItem(at: blobURL(name))
    }

    private static func optional(_ string: String?) -> SQLiteValue {
        string.map(SQLiteValue.text) ?? .null
    }

    /// The kind is part of the hash, so a path copied as text and the same path copied as a file differ.
    static func hash(kind: ClipKind, payload: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: payload)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func makeItem(_ row: [SQLiteValue]) -> ClipItem? {
        guard row.count == 17,
              let id = row[0].int64,
              let kind = row[1].string.flatMap(ClipKind.init(rawValue:)),
              let text = row[2].string,
              let createdAt = row[6].double,
              let lastUsedAt = row[7].double,
              let byteSize = row[8].int64
        else { return nil }
        return ClipItem(
            id: id, kind: kind, text: text, blobName: row[3].string,
            rtfBlobName: row[9].string, htmlBlobName: row[10].string,
            linkTitle: row[11].string, linkImageBlobName: row[12].string,
            linkCheckedAt: row[13].double.map(Date.init(timeIntervalSince1970:)),
            isEncrypted: row[14].int64 == 1,
            source: ClipSource(bundleID: row[4].string, appName: row[5].string),
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastUsedAt: Date(timeIntervalSince1970: lastUsedAt),
            byteSize: Int(byteSize),
            title: row[15].string, recognizedText: row[16].string)
    }
}

/// What became of an attempt to change a clip's text.
public enum ClipTextUpdate: Equatable, Sendable {
    case updated
    /// The new text is the old text.
    case unchanged
    /// Another clip already has this text.
    case duplicate
    /// Not a text clip, a vault clip, no such clip, or text that cannot be stored.
    case notEditable
}
