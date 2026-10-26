import Foundation

public enum ClipKind: String, CaseIterable, Sendable {
    case text
    case link
    case color
    case image
    case file
}

/// Something just read from the pasteboard, before it is stored.
public enum ClipContent: Equatable, Sendable {
    case text(String)
    /// PNG data.
    case image(Data)
    /// Absolute file paths.
    case files([String])
}

/// Formatted versions of a text clip, as apps put them on the pasteboard next to the plain string.
public struct ClipRichData: Equatable, Sendable {
    public var rtf: Data?
    public var html: Data?

    public init(rtf: Data? = nil, html: Data? = nil) {
        self.rtf = rtf
        self.html = html
    }

    public var isEmpty: Bool {
        (rtf?.isEmpty ?? true) && (html?.isEmpty ?? true)
    }
}

/// The app that was frontmost when the content was copied.
public struct ClipSource: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?

    public init(bundleID: String? = nil, appName: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
    }
}

/// A named collection of pinned clips. Pinned clips are kept when the history is pruned or cleared.
public struct ClipBoard: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    /// SF Symbol shown on the board's chip.
    public let symbolName: String
    public let itemCount: Int
    /// A locked board's clips are encrypted and shown only while the vault is unlocked.
    public let isLocked: Bool

    public init(id: Int64, name: String, symbolName: String, itemCount: Int, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.itemCount = itemCount
        self.isLocked = isLocked
    }
}

/// One stored entry of the clipboard history.
public struct ClipItem: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let kind: ClipKind
    /// Full text; for files the paths joined by newlines; empty for images.
    public let text: String
    /// File name of the stored image inside the store's blob directory; images only.
    public let blobName: String?
    /// File names of the stored RTF and HTML versions; text clips only.
    public let rtfBlobName: String?
    public let htmlBlobName: String?
    /// Title of the linked page; links only, once a preview was fetched.
    public let linkTitle: String?
    /// File name of the linked page's preview image.
    public let linkImageBlobName: String?
    /// When a preview fetch was attempted, successful or not; nil means never.
    public let linkCheckedAt: Date?
    /// True for a clip that lives in the vault: its content is stored encrypted.
    public let isEncrypted: Bool
    public let source: ClipSource
    public let createdAt: Date
    public let lastUsedAt: Date
    public let byteSize: Int
    /// A name the user gave the clip.
    public var title: String?
    /// Text read from an image clip; empty when the image was read and holds none, nil when
    /// it was not read yet.
    public var recognizedText: String?

    public init(
        id: Int64, kind: ClipKind, text: String, blobName: String?,
        rtfBlobName: String? = nil, htmlBlobName: String? = nil,
        linkTitle: String? = nil, linkImageBlobName: String? = nil, linkCheckedAt: Date? = nil,
        isEncrypted: Bool = false, source: ClipSource,
        createdAt: Date, lastUsedAt: Date, byteSize: Int,
        title: String? = nil, recognizedText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.blobName = blobName
        self.rtfBlobName = rtfBlobName
        self.htmlBlobName = htmlBlobName
        self.linkTitle = linkTitle
        self.linkImageBlobName = linkImageBlobName
        self.linkCheckedAt = linkCheckedAt
        self.isEncrypted = isEncrypted
        self.source = source
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.byteSize = byteSize
        self.title = title
        self.recognizedText = recognizedText
    }

    /// Whether the clip's text can be edited: text, links and colours outside the vault.
    public var isTextEditable: Bool {
        !isEncrypted && (kind == .text || kind == .link || kind == .color)
    }

    public var hasRichData: Bool {
        rtfBlobName != nil || htmlBlobName != nil
    }

    public var filePaths: [String] {
        kind == .file ? text.components(separatedBy: "\n") : []
    }
}
