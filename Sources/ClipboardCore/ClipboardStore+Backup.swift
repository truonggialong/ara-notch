import Foundation

/// Backup and restore of the plain history and the unlocked boards.
extension ClipboardStore {
    /// Everything outside the vault: the history newest first, and the boards that are not locked.
    public func makeBackup(at date: Date) throws -> ClipBackup {
        let openBoards = try boards().filter { !$0.isLocked }
        let boardNames = Dictionary(uniqueKeysWithValues: openBoards.map { ($0.id, $0.name) })
        let membership = try boardMembership()

        let items = try items().map { item in
            ClipBackup.Item(
                kind: item.kind.rawValue, text: item.text,
                image: imageData(for: item),
                rtf: richData(for: item)?.rtf, html: richData(for: item)?.html,
                linkTitle: item.linkTitle, linkImage: linkImageData(for: item), linkCheckedAt: item.linkCheckedAt,
                sourceBundleID: item.source.bundleID, sourceAppName: item.source.appName,
                createdAt: item.createdAt, lastUsedAt: item.lastUsedAt,
                boards: (membership[item.id] ?? []).sorted().compactMap { boardNames[$0] },
                title: item.title)
        }
        return ClipBackup(
            exportedAt: date,
            boards: openBoards.map { ClipBackup.Board(name: $0.name, symbolName: $0.symbolName) },
            items: items)
    }

    /// Merges a backup into the store. Clips already in the history are left as they are, apart
    /// from being pinned as the backup says; a board with the same name is reused. Nothing is
    /// ever pinned to a locked board.
    /// - Parameter date: when the restore happens; used for new boards and pins.
    @discardableResult
    public func restore(_ backup: ClipBackup, at date: Date) throws -> ClipBackupSummary {
        var summary = ClipBackupSummary(itemsAdded: 0, itemsAlreadyPresent: 0, itemsSkipped: 0, boardsAdded: 0)

        // Board name → id, for the boards clips may be pinned to.
        var targets: [String: Int64] = [:]
        var lockedNames = Set<String>()
        for board in try boards() {
            let key = Self.comparisonKey(board.name)
            if board.isLocked {
                lockedNames.insert(key)
            } else {
                targets[key] = board.id
            }
        }
        for board in backup.boards {
            let key = Self.comparisonKey(board.name.trimmingCharacters(in: .whitespacesAndNewlines))
            guard targets[key] == nil, !lockedNames.contains(key) else { continue }
            // A name that cannot be used, or one board too many, only loses the pins.
            guard let created = try? createBoard(name: board.name, symbolName: board.symbolName, at: date) else {
                continue
            }
            targets[key] = created.id
            summary.boardsAdded += 1
        }

        // Oldest first, so clips with equal dates keep their order.
        for entry in backup.items.reversed() {
            guard let content = Self.content(of: entry),
                  let stored = try insert(
                      content, rich: ClipRichData(rtf: entry.rtf, html: entry.html),
                      source: ClipSource(bundleID: entry.sourceBundleID, appName: entry.sourceAppName),
                      at: entry.lastUsedAt, createdAt: entry.createdAt, keepingDuplicate: true, pruning: false)
            else {
                summary.itemsSkipped += 1
                continue
            }
            if stored.isNew {
                summary.itemsAdded += 1
                if let checkedAt = entry.linkCheckedAt {
                    try setLinkPreview(id: stored.id, title: entry.linkTitle, imageData: entry.linkImage, at: checkedAt)
                }
                if let title = entry.title {
                    try setTitle(id: stored.id, title: title)
                }
            } else {
                summary.itemsAlreadyPresent += 1
            }
            for name in entry.boards {
                guard let boardID = targets[Self.comparisonKey(name)] else { continue }
                do {
                    try pin(itemID: stored.id, toBoard: boardID, at: date)
                } catch ClipboardStoreError.boardFull {
                    // The clip stays in the history, unpinned.
                }
            }
        }
        // Only now, with the pins in place, does the history limit apply.
        try prune()
        return summary
    }

    private static func content(of entry: ClipBackup.Item) -> ClipContent? {
        switch ClipKind(rawValue: entry.kind) {
        case .image:
            entry.image.map(ClipContent.image)
        case .file:
            entry.text.isEmpty ? nil : .files(entry.text.components(separatedBy: "\n"))
        case .text, .link, .color:
            .text(entry.text)
        case nil:
            nil
        }
    }
}
