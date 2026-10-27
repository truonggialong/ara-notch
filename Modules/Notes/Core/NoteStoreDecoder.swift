import Foundation

/// An attachment found in a note's data, in order of appearance.
public struct NoteStoreAttachment: Hashable, Sendable {
    public var identifier: String
    public var uti: String

    public init(identifier: String, uti: String) {
        self.identifier = identifier
        self.uti = uti
    }
}

/// A decoded note: its document, its attachments in order, and whether it has formatting the document cannot hold
/// (so a write, which rebuilds the note from the document, would drop it).
public struct DecodedNote: Hashable, Sendable {
    public var document: NoteDocument
    public var attachments: [NoteStoreAttachment]
    public var hasUnsupportedFormatting: Bool

    public init(document: NoteDocument, attachments: [NoteStoreAttachment], hasUnsupportedFormatting: Bool = false) {
        self.document = document
        self.attachments = attachments
        self.hasUnsupportedFormatting = hasUnsupportedFormatting
    }
}

public enum NoteStoreDecoderError: Error, Equatable {
    case notGzip
    case malformed(String)
}

/// Decodes `ZICNOTEDATA.ZDATA` of NoteStore.sqlite (gzip, then Notes' protobuf) into a `NoteDocument`.
/// Schema after the public apple_cloud_notes_parser work: document(2) > note(3) > note_text(2),
/// attribute_run(5).
///
/// An attribute run: length 1, paragraph_style 2, font 3, font_weight 5, underlined 6, strikethrough 7,
/// superscript 8, link 9, color 10, attachment_info 12, emphasis_style (highlight) 14. A paragraph style:
/// style_type 1, alignment 2, indent_amount 4, checklist 5, block_quote 8. A font: name 1, point_size 2, hints 3.
/// A named font other than the ones AraNotch's own writes come back with, superscript, colour, highlight and an
/// alignment other than 0 (left) are what the reader cannot show nor the writer keep: they are flagged. A size
/// alone is not: every note written through HTML carries one.
public enum NoteStoreDecoder {
    public static func decode(_ data: Data) throws -> DecodedNote {
        let message = try Gzip.decompress(data)
        var text = ""
        var runs: [Run] = []
        var sawNote = false
        var reader = ProtobufReader(message)
        while let (field, value) = try reader.next() {
            guard field == 2, case .bytes(let document) = value else { continue }
            var documentReader = ProtobufReader(document)
            while let (documentField, documentValue) = try documentReader.next() {
                guard documentField == 3, case .bytes(let note) = documentValue else { continue }
                sawNote = true
                var noteReader = ProtobufReader(note)
                while let (noteField, noteValue) = try noteReader.next() {
                    guard case .bytes(let bytes) = noteValue else { continue }
                    if noteField == 2 {
                        text = String(decoding: bytes, as: UTF8.self)
                    } else if noteField == 5 {
                        runs.append(try Run(parsing: bytes))
                    }
                }
            }
        }
        guard sawNote else { throw NoteStoreDecoderError.malformed("no note") }
        let known: Set<Int> = [0, 1, 2, 4, 100, 101, 102, 103]
        for run in runs {
            // Only an absent style or -1 is body text; anything else may be a kind this reader cannot show.
            if let style = run.styleType, style != -1, !known.contains(style) { throw NoteStoreDecoderError.malformed("style \(style)") }
        }
        let (document, attachments) = Builder(text: text, runs: runs).build()
        return DecodedNote(document: document, attachments: attachments,
                           hasUnsupportedFormatting: runs.contains(where: \.hasUnsupportedFormatting))
    }

    /// One attribute run: its length in UTF-16 units and the formatting that applies to it.
    struct Run {
        var length = 0
        var styleType: Int?
        var indent = 0
        var done = false
        var quote = false
        var weight = 0
        var underlined = false
        var strikethrough = false
        var link: URL?
        var attachment: NoteStoreAttachment?
        /// Font, superscript, colour, highlight or a non-left alignment: formatting a write would drop.
        var hasUnsupportedFormatting = false
        var fontName: String?
        var pointSize: Double?

        init(parsing data: Data) throws {
            var reader = ProtobufReader(data)
            while let (field, value) = try reader.next() {
                switch (field, value) {
                case (1, .varint(let v)): length = Int(clamping: v)
                case (2, .bytes(let b)): try parseParagraphStyle(b)
                case (5, .varint(let v)): weight = Int(clamping: v)
                case (6, .varint(let v)): underlined = v != 0
                case (7, .varint(let v)): strikethrough = v != 0
                case (9, .bytes(let b)): link = URL(string: String(decoding: b, as: UTF8.self))
                case (12, .bytes(let b)): attachment = try Self.parseAttachment(b)
                case (3, .bytes(let b)):
                    try parseFont(b)
                    if let fontName, !Self.ownFonts.contains(fontName) { hasUnsupportedFormatting = true }
                case (3, _), (10, _): hasUnsupportedFormatting = true
                case (8, .varint(let v)), (14, .varint(let v)): if v != 0 { hasUnsupportedFormatting = true }
                case (14, _): hasUnsupportedFormatting = true
                default: break
                }
            }
        }

        private mutating func parseParagraphStyle(_ data: Data) throws {
            var reader = ProtobufReader(data)
            while let (field, value) = try reader.next() {
                switch (field, value) {
                case (1, .varint(let v)): styleType = Int(truncatingIfNeeded: v)
                case (2, .varint(let v)): if v != 0 { hasUnsupportedFormatting = true }
                case (4, .varint(let v)): indent = Int(min(v, UInt64(NoteDocument.maxListIndent)))
                case (5, .bytes(let b)):
                    var checklist = ProtobufReader(b)
                    while let (checklistField, checklistValue) = try checklist.next() {
                        if checklistField == 2, case .varint(let v) = checklistValue { done = v != 0 }
                    }
                case (8, .varint(let v)): quote = v != 0
                default: break
                }
            }
        }

        /// Font names Notes gives the text AraNotch writes: body, bold headings, code.
        static let ownFonts: Set<String> = [".AppleSystemUIFont", ".AppleSystemUIFontBold", "Courier"]

        private mutating func parseFont(_ data: Data) throws {
            var reader = ProtobufReader(data)
            while let (field, value) = try reader.next() {
                switch (field, value) {
                case (1, .bytes(let b)): fontName = String(decoding: b, as: UTF8.self)
                case (2, .fixed32(let bits)): pointSize = Double(Float(bitPattern: bits))
                default: break
                }
            }
        }

        private static func parseAttachment(_ data: Data) throws -> NoteStoreAttachment {
            var identifier = "", uti = ""
            var reader = ProtobufReader(data)
            while let (field, value) = try reader.next() {
                guard case .bytes(let b) = value else { continue }
                if field == 1 { identifier = String(decoding: b, as: UTF8.self) }
                if field == 2 { uti = String(decoding: b, as: UTF8.self) }
            }
            return NoteStoreAttachment(identifier: identifier, uti: uti)
        }

        var textStyle: TextStyle {
            var style: TextStyle = []
            if weight & 1 != 0 { style.insert(.bold) }
            if weight & 2 != 0 { style.insert(.italic) }
            if underlined { style.insert(.underline) }
            if strikethrough { style.insert(.strikethrough) }
            if fontName == "Courier" { style.insert(.monospaced) }
            return style
        }
    }

    /// Turns the text and its runs into blocks, one per line.
    private struct Builder {
        let units: [UInt16]
        /// Each run with the UTF-16 offset where it starts and its attachment's position, if any.
        let placed: [(start: Int, end: Int, run: Run, attachmentIndex: Int?)]
        let attachments: [NoteStoreAttachment]

        init(text: String, runs: [Run]) {
            units = Array(text.utf16)
            var placed: [(Int, Int, Run, Int?)] = []
            var attachments: [NoteStoreAttachment] = []
            var offset = 0
            for run in runs {
                // Compared before adding: a huge length (corrupt data) must not overflow.
                let end = run.length >= units.count - offset ? units.count : offset + run.length
                var index: Int?
                if let attachment = run.attachment {
                    index = attachments.count
                    attachments.append(attachment)
                }
                placed.append((min(offset, units.count), end, run, index))
                offset = end
            }
            self.placed = placed
            self.attachments = attachments
        }

        func build() -> (document: NoteDocument, attachments: [NoteStoreAttachment]) {
            var blocks: [NoteBlock] = []
            var start = 0
            while start < units.count {
                var end = start
                while end < units.count, units[end] != 0x0A { end += 1 }
                blocks.append(contentsOf: lineBlocks(from: start, to: end))
                start = end + 1   // a trailing newline ends the last line instead of starting an empty one
            }
            return (NoteDocument(blocks: blocks), attachments)
        }

        private func covering(_ offset: Int) -> (start: Int, end: Int, run: Run, attachmentIndex: Int?)? {
            placed.first { $0.start <= offset && offset < $0.end }
        }

        /// The line's block, followed by a `.file` block for each attachment sitting inside the line's
        /// text, so nothing an inline attachment stands for (hashtag, mention, link) is hidden.
        private func lineBlocks(from start: Int, to end: Int) -> [NoteBlock] {
            let main = block(from: start, to: end)
            if end - start == 1, case .some = covering(start)?.attachmentIndex, units[start] == 0xFFFC { return [main] }
            let inline = placed.filter { entry in
                guard entry.attachmentIndex != nil else { return false }
                return entry.start >= start && entry.start < end && units[entry.start] == 0xFFFC
            }
            return [main] + inline.compactMap { entry in
                guard let index = entry.attachmentIndex, let attachment = entry.run.attachment else { return nil }
                return .file(attachmentIndex: index, name: "", uti: attachment.uti)
            }
        }

        private func block(from start: Int, to end: Int) -> NoteBlock {
            let first = covering(start)
            let paragraph = first?.run ?? Run.plain
            if end - start == 1, units[start] == 0xFFFC, let index = first?.attachmentIndex, let attachment = first?.run.attachment {
                return attachmentBlock(attachment, index: index)
            }
            let runs = textRuns(from: start, to: end)
            if paragraph.quote, paragraph.styleType == 4 { return .quote(runs) }   // quote wins: read-only later
            switch paragraph.styleType {
            case 4:
                return .code(runs.map(\.text).joined())
            case 100: return .listItem(.bullet, indent: paragraph.indent, runs)
            case 101: return .listItem(.dash, indent: paragraph.indent, runs)
            case 102: return .listItem(.numbered, indent: paragraph.indent, runs)
            case 103: return .listItem(.checklist(done: paragraph.done), indent: paragraph.indent, runs)
            default: break
            }
            if paragraph.quote { return .quote(runs) }
            switch paragraph.styleType {
            case 0: return .heading(level: 1, runs)
            case 1: return .heading(level: 2, runs)
            case 2: return .heading(level: 3, runs)
            default: break
            }
            if let level = sizeHeadingLevel(from: start, to: end) { return .heading(level: level, runs) }
            return .paragraph(runs)
        }

        /// What the HTML reader takes for a heading, from the runs' fonts: every character bold at one size, in
        /// Notes' bold system font at 21, 15 or 13 points (its form for h1–h3), or in no named font at 24, 21 or 18
        /// (what Notes keeps of AraNotch's headings). Notes keeps the sizes in points as the HTML gives them in px.
        private func sizeHeadingLevel(from start: Int, to end: Int) -> Int? {
            let runs = placed.filter { entry in
                entry.start < end && entry.end > start
                    && (max(entry.start, start)..<min(entry.end, end)).contains { units[$0] != 0x0A }
            }.map(\.run)
            guard !runs.isEmpty, runs.allSatisfy({ $0.weight & 1 != 0 }) else { return nil }
            let sizes = Set(runs.map { $0.pointSize.map { Int($0.rounded()) } })
            guard sizes.count == 1, let size = sizes.first ?? nil else { return nil }
            if runs.allSatisfy({ $0.fontName == ".AppleSystemUIFontBold" }) { return [21: 1, 15: 2, 13: 3][size] }
            if runs.allSatisfy({ $0.fontName == nil }) { return [24: 1, 21: 2, 18: 3][size] }
            return nil
        }

        private func attachmentBlock(_ attachment: NoteStoreAttachment, index: Int) -> NoteBlock {
            let uti = attachment.uti
            if ["public.jpeg", "public.png", "public.heic", "public.image", "com.compuserve.gif", "public.gif", "public.tiff"].contains(uti) {
                return .image(attachmentIndex: index)
            }
            if uti == "com.apple.notes.table" { return .table(html: "", cells: []) }
            if uti.hasPrefix("com.apple.drawing") || uti == "com.apple.paper" { return .drawing(attachmentIndex: index) }
            return .file(attachmentIndex: index, name: "", uti: uti)
        }

        /// The line's text split by run, with attachment characters dropped and equal neighbours merged.
        private func textRuns(from start: Int, to end: Int) -> [TextRun] {
            var result: [TextRun] = []
            var position = start
            while position < end {
                let covering = covering(position)
                let segmentEnd = min(covering?.end ?? end, end)
                let upper = max(segmentEnd, position + 1)
                let slice = units[position..<min(upper, end)].filter { $0 != 0xFFFC }
                let run = covering?.run ?? Run.plain
                let text = String(decoding: slice, as: UTF16.self)
                if !text.isEmpty {
                    if let last = result.last, last.style == run.textStyle, last.link == run.link {
                        result[result.count - 1].text += text
                    } else {
                        result.append(TextRun(text, style: run.textStyle, link: run.link))
                    }
                }
                position = min(upper, end)
            }
            return result
        }
    }
}

private extension NoteStoreDecoder.Run {
    static let plain: NoteStoreDecoder.Run = try! NoteStoreDecoder.Run(parsing: Data())
}
