import Foundation

/// Inline formatting of a run of text.
public struct TextStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = TextStyle(rawValue: 1 << 0)
    public static let italic = TextStyle(rawValue: 1 << 1)
    public static let underline = TextStyle(rawValue: 1 << 2)
    public static let strikethrough = TextStyle(rawValue: 1 << 3)
    public static let monospaced = TextStyle(rawValue: 1 << 4)
}

/// A piece of text with one style and an optional link.
public struct TextRun: Hashable, Sendable {
    public var text: String
    public var style: TextStyle
    public var link: URL?

    public init(_ text: String, style: TextStyle = [], link: URL? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }
}

public enum ListKind: Hashable, Sendable {
    case bullet, dash, numbered
    case checklist(done: Bool)
}

/// One block of a note, in reading order.
public enum NoteBlock: Hashable, Sendable {
    case paragraph([TextRun])
    case heading(level: Int, [TextRun])            // 1 Title, 2 Heading, 3 Subheading
    case listItem(ListKind, indent: Int, [TextRun])
    case quote([TextRun])
    case code(String)                              // a block set in monospace, whole lines
    case image(attachmentIndex: Int)               // position among the note's attachments
    case table(html: String, cells: [[String]])
    case file(attachmentIndex: Int, name: String, uti: String)
    case drawing(attachmentIndex: Int)
}

/// The content of a note as blocks, independent of how Notes stores it.
public struct NoteDocument: Hashable, Sendable {
    /// The deepest list indent kept; a deeper one (only hostile or corrupt data has it) is taken as this one.
    public static let maxListIndent = 10

    public var blocks: [NoteBlock]

    public init(blocks: [NoteBlock]) { self.blocks = blocks }

    /// The blocks joined by newlines; every attachment (image, table, file, drawing) is one U+FFFC.
    public var plainText: String {
        blocks.map { block -> String in
            switch block {
            case .paragraph(let runs), .heading(_, let runs), .listItem(_, _, let runs), .quote(let runs):
                return runs.map(\.text).joined()
            case .code(let text):
                return text
            case .image, .table, .file, .drawing:
                return "\u{FFFC}"
            }
        }.joined(separator: "\n")
    }

    /// How many blocks are images.
    public var imageCount: Int {
        blocks.filter { if case .image = $0 { true } else { false } }.count
    }
}
