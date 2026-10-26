import Foundation

/// Boards: named collections of pinned clips.
extension ClipboardStore {
    public static let maxBoards = 20
    public static let maxItemsPerBoard = 200
    public static let maxBoardNameLength = 40

    func createBoardTables() throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS boards (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                symbol TEXT NOT NULL,
                created_at REAL NOT NULL,
                is_locked INTEGER NOT NULL DEFAULT 0
            )
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS board_items (
                board_id INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                pinned_at REAL NOT NULL,
                PRIMARY KEY (board_id, item_id)
            )
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS board_items_item ON board_items (item_id)")
    }

    // MARK: - Boards

    /// All boards in creation order.
    public func boards() throws -> [ClipBoard] {
        try database.query("""
            SELECT id, name, symbol, (SELECT COUNT(*) FROM board_items WHERE board_id = boards.id), is_locked
            FROM boards ORDER BY id
            """).compactMap { row in
            guard let id = row[0].int64, let name = row[1].string, let symbol = row[2].string,
                  let count = row[3].int64
            else { return nil }
            return ClipBoard(
                id: id, name: name, symbolName: symbol, itemCount: Int(count), isLocked: row[4].int64 == 1)
        }
    }

    @discardableResult
    public func createBoard(name: String, symbolName: String, at date: Date) throws -> ClipBoard {
        let existing = try boards()
        let cleanName = try validatedBoardName(name, among: existing, excluding: nil)
        guard existing.count < Self.maxBoards else { throw ClipboardStoreError.tooManyBoards }
        try database.execute(
            "INSERT INTO boards (name, symbol, created_at) VALUES (?, ?, ?)",
            [.text(cleanName), .text(symbolName), .real(date.timeIntervalSince1970)])
        return ClipBoard(id: database.lastInsertRowID, name: cleanName, symbolName: symbolName, itemCount: 0)
    }

    public func updateBoard(id: Int64, name: String, symbolName: String) throws {
        let cleanName = try validatedBoardName(name, among: try boards(), excluding: id)
        try database.execute(
            "UPDATE boards SET name = ?, symbol = ? WHERE id = ?",
            [.text(cleanName), .text(symbolName), .integer(id)])
    }

    /// Deletes the board. Its clips stay in the history, where the usual limit applies again.
    /// A locked board needs the vault unlocked, so its clips can be decrypted back.
    public func deleteBoard(id: Int64) throws {
        if try isBoardLocked(id) {
            try releaseVaultItems(ofBoard: id)
        }
        try database.execute("DELETE FROM board_items WHERE board_id = ?", [.integer(id)])
        try database.execute("DELETE FROM boards WHERE id = ?", [.integer(id)])
        try prune()
    }

    /// Trims the name and checks it: not empty, not too long, not taken by another board.
    /// Names differing only in letter case count as the same.
    private func validatedBoardName(_ name: String, among boards: [ClipBoard], excluding id: Int64?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= Self.maxBoardNameLength else {
            throw ClipboardStoreError.invalidBoardName
        }
        let key = Self.comparisonKey(clean)
        guard !boards.contains(where: { $0.id != id && Self.comparisonKey($0.name) == key }) else {
            throw ClipboardStoreError.duplicateBoardName
        }
        return clean
    }

    /// Board names differing only in letter case or Unicode form are the same name.
    static func comparisonKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    // MARK: - Pins

    /// Pins the clip to the board. Pinning again changes nothing; an unknown clip or board is ignored.
    /// A locked board needs the vault unlocked; the clip then moves into the vault.
    public func pin(itemID: Int64, toBoard boardID: Int64, at date: Date) throws {
        guard let item = try storedItem(id: itemID), try exists("boards", id: boardID) else { return }
        let isLocked = try isBoardLocked(boardID)
        if isLocked, vaultKey == nil { throw ClipboardStoreError.vaultLocked }
        // A vault clip lives only on locked boards.
        if item.isEncrypted, !isLocked { return }

        let pinned = try database.query(
            "SELECT 1 FROM board_items WHERE board_id = ? AND item_id = ?", [.integer(boardID), .integer(itemID)])
        guard pinned.isEmpty else { return }

        let count = try database.query("SELECT COUNT(*) FROM board_items WHERE board_id = ?", [.integer(boardID)])
            .first?.first?.int64 ?? 0
        guard count < Int64(Self.maxItemsPerBoard) else { throw ClipboardStoreError.boardFull }

        if isLocked, !item.isEncrypted {
            try encrypt(item)
        }

        try database.execute(
            "INSERT INTO board_items (board_id, item_id, pinned_at) VALUES (?, ?, ?)",
            [.integer(boardID), .integer(itemID), .real(date.timeIntervalSince1970)])
    }

    /// Unpins the clip. If it is on no other board, the history limit applies to it again.
    public func unpin(itemID: Int64, fromBoard boardID: Int64) throws {
        if try isBoardLocked(boardID), vaultKey == nil { throw ClipboardStoreError.vaultLocked }
        try database.execute(
            "DELETE FROM board_items WHERE board_id = ? AND item_id = ?", [.integer(boardID), .integer(itemID)])
        try releaseFromVaultIfUnheld(itemID: itemID)
        try prune()
    }

    /// Moves a clip within its board: before another of the board's clips, or to the end when
    /// `otherID` is nil. A clip or target that is not on the board changes nothing.
    /// - Parameter date: when the move happens; a clip pinned later still goes first.
    public func moveItem(_ itemID: Int64, inBoard boardID: Int64, before otherID: Int64?, at date: Date) throws {
        if try isBoardLocked(boardID), vaultKey == nil { throw ClipboardStoreError.vaultLocked }
        var order = try storedItems(inBoard: boardID).map(\.id)
        guard itemID != otherID, let from = order.firstIndex(of: itemID) else { return }
        order.remove(at: from)
        if let otherID {
            guard let target = order.firstIndex(of: otherID) else { return }
            order.insert(itemID, at: target)
        } else {
            order.append(itemID)
        }
        // The board lists by pin date, so the new order is written as descending dates.
        for (index, id) in order.enumerated() {
            try database.execute(
                "UPDATE board_items SET pinned_at = ? WHERE board_id = ? AND item_id = ?",
                [.real(date.timeIntervalSince1970 - Double(index)), .integer(boardID), .integer(id)])
        }
    }

    /// The board's clips, most recently pinned first.
    public func items(inBoard boardID: Int64) throws -> [ClipItem] {
        let isLocked = try isBoardLocked(boardID)
        if isLocked, vaultKey == nil { throw ClipboardStoreError.vaultLocked }
        let stored = try storedItems(inBoard: boardID)
        return isLocked ? try stored.map(decrypted) : stored
    }

    /// The board's rows as stored; vault clips still carry ciphertext.
    func storedItems(inBoard boardID: Int64) throws -> [ClipItem] {
        try database.query(
            """
            SELECT \(Self.columns) FROM items
            JOIN board_items ON board_items.item_id = items.id
            WHERE board_items.board_id = ?
            ORDER BY board_items.pinned_at DESC, items.id DESC
            """,
            [.integer(boardID)]).compactMap(Self.makeItem)
    }

    /// Clip id → ids of the boards it is pinned to. Unpinned clips are absent.
    public func boardMembership() throws -> [Int64: Set<Int64>] {
        var membership: [Int64: Set<Int64>] = [:]
        for row in try database.query("SELECT item_id, board_id FROM board_items") {
            guard let itemID = row[0].int64, let boardID = row[1].int64 else { continue }
            membership[itemID, default: []].insert(boardID)
        }
        return membership
    }

    func exists(_ table: String, id: Int64) throws -> Bool {
        // `table` is one of two literals from this file, never user input.
        try !database.query("SELECT 1 FROM \(table) WHERE id = ?", [.integer(id)]).isEmpty
    }
}
