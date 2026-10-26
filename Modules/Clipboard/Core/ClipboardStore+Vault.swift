import Foundation

public enum VaultState: Equatable, Sendable {
    /// No passcode has been chosen yet.
    case notSetUp
    case locked
    case unlocked
}

/// The vault: one passcode protecting every locked board. Clips pinned to a locked board are
/// stored encrypted and belong to locked boards only; they never appear in the plain history.
extension ClipboardStore {
    public static let minPasscodeLength = 4

    func createVaultTable() throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS vault (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                salt TEXT NOT NULL,
                iterations INTEGER NOT NULL,
                wrapped_key TEXT NOT NULL
            )
            """)
    }

    // MARK: - Passcode

    public var vaultState: VaultState {
        if vaultKey != nil { return .unlocked }
        return ((try? vaultRecord()) ?? nil) == nil ? .notSetUp : .locked
    }

    /// Chooses the passcode. The vault is unlocked afterwards.
    public func createVault(passcode: String) throws {
        guard try vaultRecord() == nil else { throw ClipboardStoreError.vaultAlreadyExists }
        guard passcode.count >= Self.minPasscodeLength else { throw ClipboardStoreError.invalidPasscode }
        let vault = try VaultCrypto.makeVault(passcode: passcode)
        try write(vault.record)
        vaultKey = vault.key
    }

    public func unlockVault(passcode: String) throws {
        guard let record = try vaultRecord() else { throw ClipboardStoreError.vaultNotSetUp }
        vaultKey = try VaultCrypto.unlock(record, passcode: passcode)
    }

    /// Forgets the data key; locked boards become unreadable until the next unlock.
    public func lockVault() {
        vaultKey = nil
    }

    /// Content is not re-encrypted: only the wrapping of the data key changes.
    public func changeVaultPasscode(from old: String, to new: String) throws {
        guard let record = try vaultRecord() else { throw ClipboardStoreError.vaultNotSetUp }
        guard new.count >= Self.minPasscodeLength else { throw ClipboardStoreError.invalidPasscode }
        try write(try VaultCrypto.rewrap(record, from: old, to: new))
    }

    private func vaultRecord() throws -> VaultRecord? {
        guard let row = try database.query("SELECT salt, iterations, wrapped_key FROM vault WHERE id = 1").first,
              let salt = row[0].string.flatMap({ Data(base64Encoded: $0) }),
              let iterations = row[1].int64,
              let wrappedKey = row[2].string.flatMap({ Data(base64Encoded: $0) })
        else { return nil }
        return VaultRecord(salt: salt, iterations: Int(iterations), wrappedKey: wrappedKey)
    }

    private func write(_ record: VaultRecord) throws {
        try database.execute(
            "INSERT OR REPLACE INTO vault (id, salt, iterations, wrapped_key) VALUES (1, ?, ?, ?)",
            [
                .text(record.salt.base64EncodedString()), .integer(Int64(record.iterations)),
                .text(record.wrappedKey.base64EncodedString()),
            ])
    }

    // MARK: - Locking boards

    /// Locks or unlocks a board. Both directions need the vault unlocked, because the board's
    /// clips are encrypted or decrypted on the spot.
    public func setBoardLocked(id: Int64, _ isLocked: Bool) throws {
        guard vaultKey != nil else { throw ClipboardStoreError.vaultLocked }
        guard try exists("boards", id: id), try isBoardLocked(id) != isLocked else { return }

        if isLocked {
            try database.execute("UPDATE boards SET is_locked = 1 WHERE id = ?", [.integer(id)])
            for item in try storedItems(inBoard: id) where !item.isEncrypted {
                try encrypt(item)
            }
            // Rewrites the file, dropping pages that still held the clips in the clear.
            try database.execute("VACUUM")
        } else {
            try database.execute("UPDATE boards SET is_locked = 0 WHERE id = ?", [.integer(id)])
            for item in try storedItems(inBoard: id) {
                try releaseFromVaultIfUnheld(itemID: item.id)
            }
        }
    }

    func isBoardLocked(_ id: Int64) throws -> Bool {
        try database.query("SELECT is_locked FROM boards WHERE id = ?", [.integer(id)]).first?.first?.int64 == 1
    }

    /// Before a locked board is deleted: its clips go back to the history unless another locked
    /// board still holds them.
    func releaseVaultItems(ofBoard id: Int64) throws {
        guard vaultKey != nil else { throw ClipboardStoreError.vaultLocked }
        let items = try storedItems(inBoard: id)
        try database.execute("DELETE FROM board_items WHERE board_id = ?", [.integer(id)])
        for item in items {
            try releaseFromVaultIfUnheld(itemID: item.id)
        }
    }

    // MARK: - Moving clips in and out of the vault

    /// Encrypts a plain clip in place and removes it from unlocked boards.
    func encrypt(_ item: ClipItem) throws {
        guard let vaultKey else { throw ClipboardStoreError.vaultLocked }
        guard let plainHash = try database.query("SELECT content_hash FROM items WHERE id = ?", [.integer(item.id)])
            .first?.first?.string
        else { return }

        func sealedText(_ text: String) throws -> String {
            try VaultCrypto.seal(Data(text.utf8), with: vaultKey).base64EncodedString()
        }
        /// Replaces a plain file with an encrypted one under a name that reveals nothing.
        func sealedBlob(_ name: String?) throws -> String? {
            guard let name else { return nil }
            let vaultName = "v-" + VaultCrypto.keyedHash(name, with: vaultKey)
            if let data = try? Data(contentsOf: blobURL(name)) {
                try VaultCrypto.seal(data, with: vaultKey).write(to: blobURL(vaultName), options: .atomic)
            }
            removeBlob(name)
            return vaultName
        }

        try database.execute(
            """
            UPDATE items SET is_encrypted = 1, text = ?, link_title = ?, content_hash = ?,
                             blob_name = ?, rtf_blob = ?, html_blob = ?, link_image_blob = ?
            WHERE id = ?
            """,
            [
                .text(try sealedText(item.text)),
                Self.optionalText(try item.linkTitle.map(sealedText)),
                .text("v:" + VaultCrypto.keyedHash(plainHash, with: vaultKey)),
                Self.optionalText(try sealedBlob(item.blobName)),
                Self.optionalText(try sealedBlob(item.rtfBlobName)),
                Self.optionalText(try sealedBlob(item.htmlBlobName)),
                Self.optionalText(try sealedBlob(item.linkImageBlobName)),
                .integer(item.id),
            ])
        try database.execute(
            "DELETE FROM board_items WHERE item_id = ? AND board_id IN (SELECT id FROM boards WHERE is_locked = 0)",
            [.integer(item.id)])
    }

    /// A vault clip with its text and link title decrypted. File names stay the encrypted ones;
    /// the blob readers decrypt on access.
    func decrypted(_ item: ClipItem) throws -> ClipItem {
        guard item.isEncrypted else { return item }
        guard let vaultKey else { throw ClipboardStoreError.vaultLocked }

        func openedText(_ text: String) throws -> String {
            guard let sealed = Data(base64Encoded: text) else { throw ClipboardStoreError.sqlite("corrupt vault clip") }
            return String(decoding: try VaultCrypto.open(sealed, with: vaultKey), as: UTF8.self)
        }
        return ClipItem(
            id: item.id, kind: item.kind, text: try openedText(item.text), blobName: item.blobName,
            rtfBlobName: item.rtfBlobName, htmlBlobName: item.htmlBlobName,
            linkTitle: try item.linkTitle.map(openedText), linkImageBlobName: item.linkImageBlobName,
            linkCheckedAt: item.linkCheckedAt, isEncrypted: true, source: item.source,
            createdAt: item.createdAt, lastUsedAt: item.lastUsedAt, byteSize: item.byteSize)
    }

    /// Returns a vault clip to the plain history once no locked board holds it any more.
    /// If the history already has the same content, the two become one clip.
    func releaseFromVaultIfUnheld(itemID: Int64) throws {
        guard let stored = try storedItem(id: itemID), stored.isEncrypted else { return }
        let stillHeld = try !database.query(
            """
            SELECT 1 FROM board_items JOIN boards ON boards.id = board_items.board_id
            WHERE board_items.item_id = ? AND boards.is_locked = 1 LIMIT 1
            """,
            [.integer(itemID)]).isEmpty
        guard !stillHeld else { return }
        guard let vaultKey else { throw ClipboardStoreError.vaultLocked }

        let plain = try decrypted(stored)
        func opened(_ name: String?) -> Data? {
            guard let name, let data = try? Data(contentsOf: blobURL(name)) else { return nil }
            return try? VaultCrypto.open(data, with: vaultKey)
        }
        let image = opened(stored.blobName)
        let rtf = opened(stored.rtfBlobName)
        let html = opened(stored.htmlBlobName)
        let linkImage = opened(stored.linkImageBlobName)
        let vaultBlobs = [stored.blobName, stored.rtfBlobName, stored.htmlBlobName, stored.linkImageBlobName]
            .compactMap { $0 }

        let payload = stored.kind == .image ? (image ?? Data()) : Data(plain.text.utf8)
        let plainHash = Self.hash(kind: stored.kind, payload: payload)

        if let twinID = try database.query(
            "SELECT id FROM items WHERE content_hash = ? AND id != ?", [.text(plainHash), .integer(itemID)])
            .first?.first?.int64 {
            // The same content was copied again meanwhile: keep that clip and move the pins to it.
            try database.execute(
                """
                INSERT OR IGNORE INTO board_items (board_id, item_id, pinned_at)
                SELECT board_id, ?, pinned_at FROM board_items WHERE item_id = ?
                """,
                [.integer(twinID), .integer(itemID)])
            try database.execute("DELETE FROM board_items WHERE item_id = ?", [.integer(itemID)])
            try database.execute("DELETE FROM items WHERE id = ?", [.integer(itemID)])
            vaultBlobs.forEach(removeBlob)
            return
        }

        /// Writes a decrypted file under its ordinary name; nil when the clip has no such file.
        func restored(_ data: Data?, suffix: String) throws -> String? {
            guard let data else { return nil }
            let name = plainHash + suffix
            try data.write(to: blobURL(name), options: .atomic)
            return name
        }
        try database.execute(
            """
            UPDATE items SET is_encrypted = 0, text = ?, link_title = ?, content_hash = ?,
                             blob_name = ?, rtf_blob = ?, html_blob = ?, link_image_blob = ?
            WHERE id = ?
            """,
            [
                .text(plain.text), Self.optionalText(plain.linkTitle), .text(plainHash),
                Self.optionalText(try restored(image, suffix: image.map { ".\(ClipImageData.fileExtension(of: $0))" } ?? ".png")),
                Self.optionalText(try restored(rtf, suffix: ".rtf")),
                Self.optionalText(try restored(html, suffix: ".html")),
                Self.optionalText(try restored(linkImage, suffix: ".preview")),
                .integer(itemID),
            ])
        vaultBlobs.forEach(removeBlob)
    }

    private static func optionalText(_ string: String?) -> SQLiteValue {
        string.map(SQLiteValue.text) ?? .null
    }
}
