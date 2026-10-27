import AppKit
import NotesCore

/// How wide or tall pictures are drawn in the text.
public enum NoteImageSize: Equatable { case thumbnail, fitWidth(CGFloat) }   // thumbnail: at most 64 pt tall

/// The custom attributes the editor text carries so a note can be read back from it.
enum NoteAttribute {
    static let block = NSAttributedString.Key("AraNotesBlock")
    static let indent = NSAttributedString.Key("AraNotesIndent")
    static let decoration = NSAttributedString.Key("AraNotesDecoration")
    static let attachmentIndex = NSAttributedString.Key("AraNotesAttachmentIndex")
    static let attachmentKind = NSAttributedString.Key("AraNotesAttachmentKind")
    static let fileName = NSAttributedString.Key("AraNotesFileName")
    static let fileUTI = NSAttributedString.Key("AraNotesFileUTI")
    static let tableHTML = NSAttributedString.Key("AraNotesTableHTML")
    static let tableCells = NSAttributedString.Key("AraNotesTableCells")   // JSON, so it survives a pasteboard
}

/// What kind of paragraph a line of the text is.
enum NoteBlockKind: String {
    case paragraph, h1, h2, h3, bullet, dash, numbered, quote, code
    case checklistDone = "checklist-done"
    case checklistOpen = "checklist-open"

    var isHeading: Bool { self == .h1 || self == .h2 || self == .h3 }
    var isList: Bool {
        switch self {
        case .bullet, .dash, .numbered, .checklistDone, .checklistOpen: true
        default: false
        }
    }
}

enum NoteAttributedText {
    static let indentStep: CGFloat = 18

    // MARK: Fonts and attributes

    static func font(kind: NoteBlockKind, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        let useMono = mono || kind == .code
        let size: CGFloat
        switch kind {
        case .h1: size = 21
        case .h2: size = 15
        case .h3: size = 13
        default: size = useMono ? 12 : 13
        }
        var font = useMono ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        var traits = font.fontDescriptor.symbolicTraits
        if bold || kind.isHeading { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if traits != font.fontDescriptor.symbolicTraits {
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: size) ?? font
        }
        return font
    }

    /// The inline flags a font carries; the bold of a heading and the monospace of code are the block's, not the user's.
    static func flags(of font: NSFont?, kind: NoteBlockKind) -> (bold: Bool, italic: Bool, mono: Bool) {
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        return (traits.contains(.bold) && !kind.isHeading, traits.contains(.italic), traits.contains(.monoSpace) && kind != .code)
    }

    static func paragraphStyle(kind: NoteBlockKind, indent: Int) -> NSParagraphStyle {
        let indent = min(max(indent, 0), NoteDocument.maxListIndent)
        let style = NSMutableParagraphStyle()
        if kind.isList {
            style.firstLineHeadIndent = indentStep * CGFloat(indent)
            style.headIndent = indentStep * CGFloat(indent + 1)
        } else if kind == .quote {
            style.firstLineHeadIndent = 12
            style.headIndent = 12
        }
        return style
    }

    /// The attributes shared by every character of a paragraph, newline included.
    static func blockAttributes(kind: NoteBlockKind, indent: Int = 0) -> [NSAttributedString.Key: Any] {
        let indent = min(max(indent, 0), NoteDocument.maxListIndent)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(kind: kind), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(kind: kind, indent: indent), NoteAttribute.block: kind.rawValue,
        ]
        if kind.isList { attributes[NoteAttribute.indent] = indent }
        return attributes
    }

    /// What typing in an empty text gets.
    static func typingAttributes(for kind: NoteBlockKind) -> [NSAttributedString.Key: Any] { blockAttributes(kind: kind) }

    static func kind(of attributes: [NSAttributedString.Key: Any]) -> NoteBlockKind {
        (attributes[NoteAttribute.block] as? String).flatMap(NoteBlockKind.init(rawValue:)) ?? .paragraph
    }

    // MARK: Document to text

    /// Builds the cells AppKit draws, so it runs on the main actor.
    @MainActor static func make(_ doc: NoteDocument, images: [Int: NSImage], imageSize: NoteImageSize) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var counters: [Int: Int] = [:]
        for (position, block) in doc.blocks.enumerated() {
            switch block {
            case .listItem(let list, let indent, let runs):
                let kind: NoteBlockKind
                var prefix: String
                switch list {
                case .bullet: kind = .bullet; prefix = "• "
                case .dash: kind = .dash; prefix = "– "
                case .numbered: kind = .numbered; prefix = ""
                case .checklist(let done): kind = done ? .checklistDone : .checklistOpen; prefix = done ? "☑ " : "☐ "
                }
                if kind == .numbered {
                    counters = counters.filter { $0.key <= indent }
                    counters[indent, default: 0] += 1
                    prefix = "\(counters[indent]!). "
                } else {
                    counters = counters.filter { $0.key < indent }
                }
                out.append(line(kind, indent: indent, prefix: prefix, runs))
            case .paragraph(let runs):
                counters = [:]
                out.append(line(.paragraph, runs: runs))
            case .heading(let level, let runs):
                counters = [:]
                out.append(line([.h1, .h2, .h3][min(max(level, 1), 3) - 1], runs: runs))
            case .quote(let runs):
                counters = [:]
                out.append(line(.quote, runs: runs))
            case .code(let text):
                counters = [:]
                for codeLine in text.components(separatedBy: "\n") { out.append(line(.code, runs: [TextRun(codeLine)])) }
            case .image(let index):
                counters = [:]
                let image = images[index]
                let attachment = NSTextAttachment()
                let size = imageDrawSize(image?.size, imageSize)
                attachment.image = image ?? placeholder(size)
                attachment.bounds = CGRect(origin: .zero, size: size)
                out.append(attachmentLine(attachment, kind: "image", index: index))
            case .table(let html, let cells):
                counters = [:]
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NoteAttachmentCell(content: .table(cells))
                let json = (try? JSONEncoder().encode(cells)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                out.append(attachmentLine(attachment, kind: "table", index: position,
                                          extra: [NoteAttribute.tableHTML: html, NoteAttribute.tableCells: json]))
            case .file(let index, let name, let uti):
                counters = [:]
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NoteAttachmentCell(content: .file(name: name, uti: uti))
                out.append(attachmentLine(attachment, kind: "file", index: index,
                                          extra: [NoteAttribute.fileName: name, NoteAttribute.fileUTI: uti]))
            case .drawing(let index):
                counters = [:]
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NoteAttachmentCell(content: .drawing)
                out.append(attachmentLine(attachment, kind: "drawing", index: index))
            }
        }
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }   // no newline at the end
        return out
    }

    /// One paragraph with its newline.
    private static func line(_ kind: NoteBlockKind, indent: Int = 0, prefix: String = "", _ runs: [TextRun]) -> NSAttributedString {
        let base = blockAttributes(kind: kind, indent: indent)
        let result = NSMutableAttributedString()
        if !prefix.isEmpty {
            var decoration = base
            decoration[NoteAttribute.decoration] = true
            result.append(NSAttributedString(string: prefix, attributes: decoration))
        }
        for run in runs where !run.text.isEmpty {
            var attributes = base
            attributes[.font] = font(kind: kind, bold: run.style.contains(.bold), italic: run.style.contains(.italic),
                                     mono: run.style.contains(.monospaced))
            if run.style.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.style.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        result.append(NSAttributedString(string: "\n", attributes: base))
        return result
    }

    private static func line(_ kind: NoteBlockKind, runs: [TextRun]) -> NSAttributedString { line(kind, indent: 0, prefix: "", runs) }

    private static func attachmentLine(_ attachment: NSTextAttachment, kind: String, index: Int,
                                       extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        let base = blockAttributes(kind: .paragraph)
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes(base, range: NSRange(location: 0, length: result.length))
        result.addAttributes(extra, range: NSRange(location: 0, length: result.length))
        result.addAttributes([NoteAttribute.attachmentKind: kind, NoteAttribute.attachmentIndex: index],
                             range: NSRange(location: 0, length: result.length))
        result.append(NSAttributedString(string: "\n", attributes: base))
        return result
    }

    static func imageDrawSize(_ natural: NSSize?, _ mode: NoteImageSize) -> NSSize {
        guard let natural, natural.width > 0, natural.height > 0 else {
            switch mode {
            case .thumbnail: return NSSize(width: 96, height: 64)
            case .fitWidth(let width): return NSSize(width: width, height: (width * 0.6).rounded())
            }
        }
        switch mode {
        case .thumbnail:
            let height = min(64, natural.height)
            return NSSize(width: natural.width * height / natural.height, height: height)
        case .fitWidth(let width):
            let scale = min(1, width / natural.width)
            return NSSize(width: natural.width * scale, height: natural.height * scale)
        }
    }

    /// A grey box for a picture that is not loaded yet.
    private static func placeholder(_ size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.systemGray.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            return true
        }
    }

    // MARK: Text to document

    static func document(from text: NSAttributedString, original: NoteDocument) -> NoteDocument {
        let string = text.string as NSString
        guard string.length > 0 else { return NoteDocument(blocks: []) }
        var blocks: [NoteBlock] = []
        var codeLines: [String] = []
        func flushCode() {
            if !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))); codeLines = [] }
        }
        func emit(_ block: NoteBlock) { flushCode(); blocks.append(block) }

        var start = 0
        while true {
            let newline = string.range(of: "\n", range: NSRange(location: start, length: string.length - start)).location
            let end = newline == NSNotFound ? string.length : newline
            let range = NSRange(location: start, length: end - start)
            let attributeLocation = range.length > 0 ? start : (newline == NSNotFound ? nil : newline)
            let attributes = attributeLocation.map { text.attributes(at: $0, effectiveRange: nil) } ?? [:]
            paragraph(range, kind: kind(of: attributes), indent: min(max(attributes[NoteAttribute.indent] as? Int ?? 0, 0), NoteDocument.maxListIndent),
                      text: text, original: original, emit: emit, code: { codeLines.append($0) })
            if newline == NSNotFound { break }
            start = newline + 1
        }
        flushCode()
        return NoteDocument(blocks: blocks)
    }

    private static func paragraph(_ range: NSRange, kind: NoteBlockKind, indent: Int, text: NSAttributedString, original: NoteDocument,
                                  emit: (NoteBlock) -> Void, code: (String) -> Void) {
        let string = text.string as NSString
        var runs: [TextRun] = []
        var emitted = false

        func flushRuns() {
            guard !runs.isEmpty else { return }
            let block: NoteBlock
            switch kind {
            case .paragraph: block = .paragraph(runs)
            case .h1: block = .heading(level: 1, runs)
            case .h2: block = .heading(level: 2, runs)
            case .h3: block = .heading(level: 3, runs)
            case .bullet: block = .listItem(.bullet, indent: indent, runs)
            case .dash: block = .listItem(.dash, indent: indent, runs)
            case .numbered: block = .listItem(.numbered, indent: indent, runs)
            case .checklistDone: block = .listItem(.checklist(done: true), indent: indent, runs)
            case .checklistOpen: block = .listItem(.checklist(done: false), indent: indent, runs)
            case .quote: block = .quote(runs)
            case .code:
                code(runs.map(\.text).joined())
                runs = []
                emitted = true
                return
            }
            emit(block)
            runs = []
            emitted = true
        }

        // Only the exact leading mark is display-only; anything else that carries the attribute (typed text that
        // inherited it) is text.
        let body = NSRange(location: range.location + leadingMarkLength(text, range), length: range.length - leadingMarkLength(text, range))
        text.enumerateAttributes(in: body, options: []) { attributes, sub, _ in
            let flags = flags(of: attributes[.font] as? NSFont, kind: kind)
            var style: TextStyle = []
            if flags.bold { style.insert(.bold) }
            if flags.italic { style.insert(.italic) }
            if flags.mono { style.insert(.monospaced) }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { style.insert(.underline) }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { style.insert(.strikethrough) }
            let link = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap(URL.init(string:))

            var piece = ""
            func flushPiece() {
                guard !piece.isEmpty else { return }
                if let last = runs.last, last.style == style, last.link == link { runs[runs.count - 1].text += piece }
                else { runs.append(TextRun(piece, style: style, link: link)) }
                piece = ""
            }
            // Whole slices, never single UTF-16 units, so surrogate pairs and combining marks stay intact.
            var sliceStart = sub.location
            func takeSlice(upTo end: Int) {
                if end > sliceStart { piece += string.substring(with: NSRange(location: sliceStart, length: end - sliceStart)) }
            }
            for offset in sub.location..<(sub.location + sub.length)
            where string.character(at: offset) == 0xFFFC && attributes[.attachment] != nil {
                guard let block = attachmentBlock(attributes, original: original) else { continue }
                takeSlice(upTo: offset)
                flushPiece()
                flushRuns()
                emit(block)
                emitted = true
                sliceStart = offset + 1
            }
            takeSlice(upTo: sub.location + sub.length)
            flushPiece()
        }
        flushRuns()
        if !emitted { // an empty paragraph, or a list item with nothing after its mark
            runs = []
            switch kind {
            case .code: code("")
            case .paragraph: emit(.paragraph([]))
            case .h1: emit(.heading(level: 1, []))
            case .h2: emit(.heading(level: 2, []))
            case .h3: emit(.heading(level: 3, []))
            case .bullet: emit(.listItem(.bullet, indent: indent, []))
            case .dash: emit(.listItem(.dash, indent: indent, []))
            case .numbered: emit(.listItem(.numbered, indent: indent, []))
            case .checklistDone: emit(.listItem(.checklist(done: true), indent: indent, []))
            case .checklistOpen: emit(.listItem(.checklist(done: false), indent: indent, []))
            case .quote: emit(.quote([]))
            }
        }
    }

    /// The length of the display-only mark at the start of a paragraph: "• ", "– ", "☐ ", "☑ " or "12. ", and only
    /// when those characters carry the decoration attribute.
    private static func leadingMarkLength(_ text: NSAttributedString, _ range: NSRange) -> Int {
        var span = 0
        while span < range.length, text.attribute(NoteAttribute.decoration, at: range.location + span, effectiveRange: nil) != nil { span += 1 }
        guard span > 0 else { return 0 }
        let lead = (text.string as NSString).substring(with: NSRange(location: range.location, length: span))
        if let first = lead.first, "•–☐☑".contains(first), lead.dropFirst().first == " " { return first.utf16.count + 1 }
        var digits = 0
        let units = Array(lead.utf16)
        while digits < units.count, units[digits] >= 0x30, units[digits] <= 0x39 { digits += 1 }
        if digits > 0, digits + 1 < units.count, units[digits] == 0x2E, units[digits + 1] == 0x20 { return digits + 2 }
        return 0
    }

    /// Typing attributes without the display-only mark, so typed text is never mistaken for one.
    static func cleanTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var clean = attributes
        clean[NoteAttribute.decoration] = nil
        return clean
    }

    private static func attachmentBlock(_ attributes: [NSAttributedString.Key: Any], original: NoteDocument) -> NoteBlock? {
        guard let kind = attributes[NoteAttribute.attachmentKind] as? String,
              let index = attributes[NoteAttribute.attachmentIndex] as? Int else { return nil }
        switch kind {
        case "image": return .image(attachmentIndex: index)
        case "drawing": return .drawing(attachmentIndex: index)
        case "file":
            return .file(attachmentIndex: index, name: attributes[NoteAttribute.fileName] as? String ?? "",
                         uti: attributes[NoteAttribute.fileUTI] as? String ?? "public.data")
        case "table":
            if let html = attributes[NoteAttribute.tableHTML] as? String,
               let json = (attributes[NoteAttribute.tableCells] as? String)?.data(using: .utf8),
               let cells = try? JSONDecoder().decode([[String]].self, from: json) {
                return .table(html: html, cells: cells)
            }
            return original.blocks.indices.contains(index) && { if case .table = original.blocks[index] { true } else { false } }()
                ? original.blocks[index] : nil
        default: return nil
        }
    }
}
