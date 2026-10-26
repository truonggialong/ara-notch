import Foundation

public enum ClipBackupError: Error, Equatable {
    /// The file is not a clipboard backup, or is damaged.
    case notABackup
    /// The backup was written by a newer version of the app.
    case newerVersion(Int)
}

/// The clipboard history and its boards as one self-contained value that can be written to a
/// file. Vault clips and locked boards are never part of it: a backup is not encrypted.
public struct ClipBackup: Codable, Equatable, Sendable {
    public static let formatName = "aranotch-clipboard-backup"
    public static let currentVersion = 1
    /// Extension of backup files.
    public static let fileExtension = "aranotchbackup"

    public struct Board: Codable, Equatable, Sendable {
        public var name: String
        public var symbolName: String

        public init(name: String, symbolName: String) {
            self.name = name
            self.symbolName = symbolName
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        /// A `ClipKind` raw value.
        public var kind: String
        public var text: String
        /// PNG data of an image clip.
        public var image: Data?
        public var rtf: Data?
        public var html: Data?
        public var linkTitle: String?
        public var linkImage: Data?
        public var linkCheckedAt: Date?
        /// The name the user gave the clip; absent in backups made before clips could be named.
        public var title: String?
        public var sourceBundleID: String?
        public var sourceAppName: String?
        public var createdAt: Date
        public var lastUsedAt: Date
        /// Names of the boards the clip is pinned to.
        public var boards: [String]

        public init(
            kind: String, text: String, image: Data? = nil, rtf: Data? = nil, html: Data? = nil,
            linkTitle: String? = nil, linkImage: Data? = nil, linkCheckedAt: Date? = nil,
            sourceBundleID: String? = nil, sourceAppName: String? = nil,
            createdAt: Date, lastUsedAt: Date, boards: [String] = [], title: String? = nil
        ) {
            self.title = title
            self.kind = kind
            self.text = text
            self.image = image
            self.rtf = rtf
            self.html = html
            self.linkTitle = linkTitle
            self.linkImage = linkImage
            self.linkCheckedAt = linkCheckedAt
            self.sourceBundleID = sourceBundleID
            self.sourceAppName = sourceAppName
            self.createdAt = createdAt
            self.lastUsedAt = lastUsedAt
            self.boards = boards
        }
    }

    public var format: String
    public var version: Int
    public var exportedAt: Date
    /// In creation order.
    public var boards: [Board]
    /// Newest first.
    public var items: [Item]

    public init(exportedAt: Date, boards: [Board], items: [Item]) {
        format = Self.formatName
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.boards = boards
        self.items = items
    }

    /// The backup as the contents of a file: JSON, with binary data in Base64.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ClipBackup {
        struct Header: Decodable {
            let format: String
            let version: Int
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatName else {
            throw ClipBackupError.notABackup
        }
        guard header.version <= currentVersion else {
            throw ClipBackupError.newerVersion(header.version)
        }
        guard let backup = try? decoder.decode(ClipBackup.self, from: data) else {
            throw ClipBackupError.notABackup
        }
        return backup
    }
}

/// What restoring a backup did.
public struct ClipBackupSummary: Equatable, Sendable {
    public var itemsAdded: Int
    /// Clips of the backup that the history already held; they were left as they are.
    public var itemsAlreadyPresent: Int
    /// Entries that could not be used: empty, too large, or of an unknown kind.
    public var itemsSkipped: Int
    public var boardsAdded: Int

    public init(itemsAdded: Int, itemsAlreadyPresent: Int, itemsSkipped: Int, boardsAdded: Int) {
        self.itemsAdded = itemsAdded
        self.itemsAlreadyPresent = itemsAlreadyPresent
        self.itemsSkipped = itemsSkipped
        self.boardsAdded = boardsAdded
    }
}
