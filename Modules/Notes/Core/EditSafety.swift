import Foundation

/// Why a note may not be written back.
public enum ReadOnlyReason: Hashable, Sendable {
    case checklist, numberedList, quote, file, drawing, locked, listsUnknown
    /// An image of the note could not be read, so a write would have to drop it.
    case imagesUnavailable
    /// What the editor would show differs from the note's own text, so a write could lose content.
    case unreadable
    /// The note has formatting AraNotch cannot write back (font, colour, highlight, superscript, alignment):
    /// a write would drop it.
    case formatting
    /// Notes' database cannot be read (no Full Disk Access): quotes, colours and the like cannot be seen, so a write
    /// could drop them. The owner chose view only over editing with a warning (2026-10-27).
    case needsFullDiskAccess
}

public enum EditSafety: Hashable, Sendable {
    case editable
    case readOnly([ReadOnlyReason])

    /// full: the document from the database (nil when unavailable). html: the document read through AppleScript.
    /// plainText: the note's own `plaintext` from AppleScript. The document that would be edited is `full ?? html`.
    /// unsupportedFormatting: the database showed formatting the document cannot hold (`DecodedNote`).
    public static func check(full: NoteDocument?, html: NoteDocument, isLocked: Bool, plainText: String,
                             unsupportedFormatting: Bool = false) -> EditSafety {
        if isLocked { return .readOnly([.locked]) }
        let edited = full ?? html
        var found = Set<ReadOnlyReason>()
        for block in edited.blocks {
            switch block {
            case .listItem(.checklist, _, _): found.insert(.checklist)
            case .listItem(.numbered, _, _): found.insert(.numberedList)
            case .quote: found.insert(.quote)
            case .file: found.insert(.file)
            case .drawing: found.insert(.drawing)
            default: break
            }
        }
        if full == nil, edited.blocks.contains(where: { if case .listItem = $0 { true } else { false } }) {
            // Without the database, list kinds cannot be told apart, so no list is safe to rewrite.
            found.insert(.listsUnknown)
        }
        if normalise(edited.plainText) != normalise(plainText) { found.insert(.unreadable) }
        if full != nil, unsupportedFormatting { found.insert(.formatting) }

        return make(found)
    }

    /// This safety with one more reason; reasons stay unique and in declaration order.
    public func adding(_ reason: ReadOnlyReason) -> EditSafety {
        guard case .readOnly(let reasons) = self else { return .readOnly([reason]) }
        return Self.make(Set(reasons).union([reason]))
    }

    private static let order: [ReadOnlyReason] = [
        .needsFullDiskAccess, .checklist, .numberedList, .quote, .file, .drawing, .formatting, .locked, .listsUnknown,
        .imagesUnavailable, .unreadable,
    ]

    private static func make(_ found: Set<ReadOnlyReason>) -> EditSafety {
        let reasons = order.filter(found.contains)
        return reasons.isEmpty ? .editable : .readOnly(reasons)
    }

    /// Line endings unified, trailing spaces and tabs trimmed per line, trailing empty lines dropped.
    static func normalise(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        var lines = unified.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var s = Substring(line)
            while let last = s.last, last == " " || last == "\t" { s.removeLast() }
            return String(s)
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
