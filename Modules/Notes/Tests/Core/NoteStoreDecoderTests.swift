import Foundation
import Testing
@testable import NotesCore

@Suite struct NoteStoreDecoderTests {
    /// One attribute run of the synthetic note.
    struct Run {
        var length: Int
        var style: Int?
        var indent = 0
        var done: Bool?
        var weight = 0
        var underlined = false
        var strikethrough = false
        var link: String?
        var attachment: (id: String, uti: String)?
        var quote = false
    }

    static func protobuf(text: String, runs: [Run], extra: (inout ProtobufWriter) -> Void = { _ in }) -> Data {
        var root = ProtobufWriter()
        root.message(2) { document in
            document.message(3) { note in
                note.string(2, text)
                for run in runs {
                    note.message(5) { r in
                        r.varint(1, UInt64(run.length))
                        if run.style != nil || run.quote {
                            r.message(2) { p in
                                if let style = run.style { p.varint(1, UInt64(style)) }
                                if run.indent != 0 { p.varint(4, UInt64(run.indent)) }
                                if let done = run.done {
                                    p.message(5) { c in
                                        c.string(1, "uuid")
                                        c.varint(2, done ? 1 : 0)
                                    }
                                }
                                if run.quote { p.varint(8, 1) }
                            }
                        }
                        if run.weight != 0 { r.varint(5, UInt64(run.weight)) }
                        if run.underlined { r.varint(6, 1) }
                        if run.strikethrough { r.varint(7, 1) }
                        if let link = run.link { r.string(9, link) }
                        if let attachment = run.attachment {
                            r.message(12) { a in
                                a.string(1, attachment.id)
                                a.string(2, attachment.uti)
                            }
                        }
                    }
                }
                extra(&note)
            }
        }
        return root.data
    }

    static func gzip(_ data: Data) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("in.bin")
        try data.write(to: input)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-c", input.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return output
    }

    static func decode(text: String, runs: [Run]) throws -> DecodedNote {
        try NoteStoreDecoder.decode(gzip(protobuf(text: text, runs: runs)))
    }

    @Test func decodesChecklistWithDoneState() throws {
        let result = try Self.decode(text: "việc 1\nviệc 2\n", runs: [
            Run(length: 7, style: 103, done: true), Run(length: 7, style: 103, done: false),
        ])
        #expect(result.document.blocks == [
            .listItem(.checklist(done: true), indent: 0, [TextRun("việc 1")]),
            .listItem(.checklist(done: false), indent: 0, [TextRun("việc 2")]),
        ])
    }

    @Test func decodesNumberedAndQuote() throws {
        let result = try Self.decode(text: "one\ntwo\nsaid\nplain", runs: [
            Run(length: 4, style: 102), Run(length: 4, style: 102, indent: 1),
            Run(length: 5, quote: true), Run(length: 5),
        ])
        #expect(result.document.blocks == [
            .listItem(.numbered, indent: 0, [TextRun("one")]),
            .listItem(.numbered, indent: 1, [TextRun("two")]),
            .quote([TextRun("said")]),
            .paragraph([TextRun("plain")]),
        ])
    }

    @Test func decodesHeadingsBulletsDashesAndCode() throws {
        let result = try Self.decode(text: "T\nH\nS\nb\nd\nlet x\n", runs: [
            Run(length: 2, style: 0), Run(length: 2, style: 1), Run(length: 2, style: 2),
            Run(length: 2, style: 100), Run(length: 2, style: 101), Run(length: 6, style: 4),
        ])
        #expect(result.document.blocks == [
            .heading(level: 1, [TextRun("T")]), .heading(level: 2, [TextRun("H")]), .heading(level: 3, [TextRun("S")]),
            .listItem(.bullet, indent: 0, [TextRun("b")]), .listItem(.dash, indent: 0, [TextRun("d")]),
            .code("let x"),
        ])
    }

    @Test func decodesBoldItalicLink() throws {
        // "a bold it both u s link"
        let result = try Self.decode(text: "a bold it both u s link", runs: [
            Run(length: 2), Run(length: 4, weight: 1), Run(length: 1), Run(length: 2, weight: 2), Run(length: 1),
            Run(length: 4, weight: 3), Run(length: 1), Run(length: 1, underlined: true), Run(length: 1),
            Run(length: 1, strikethrough: true), Run(length: 1), Run(length: 4, link: "https://example.com/"),
        ])
        #expect(result.document.blocks == [.paragraph([
            TextRun("a "), TextRun("bold", style: .bold), TextRun(" "), TextRun("it", style: .italic), TextRun(" "),
            TextRun("both", style: [.bold, .italic]), TextRun(" "), TextRun("u", style: .underline), TextRun(" "),
            TextRun("s", style: .strikethrough), TextRun(" "), TextRun("link", link: URL(string: "https://example.com/")),
        ])])
    }

    @Test func mergesAdjacentRunsWithTheSameStyle() throws {
        let result = try Self.decode(text: "abcd", runs: [Run(length: 2), Run(length: 2)])
        #expect(result.document.blocks == [.paragraph([TextRun("abcd")])])
    }

    @Test func countsUTF16ForEmoji() throws {
        let result = try Self.decode(text: "😀a", runs: [Run(length: 2, weight: 1), Run(length: 1)])
        #expect(result.document.blocks == [.paragraph([TextRun("😀", style: .bold), TextRun("a")])])
    }

    @Test func mapsAttachmentsByUTI() throws {
        let result = try Self.decode(text: "\u{FFFC}\n\u{FFFC}\n\u{FFFC}\n\u{FFFC}\n\u{FFFC}\n", runs: [
            Run(length: 2, attachment: ("i0", "public.jpeg")),
            Run(length: 2, attachment: ("i1", "com.apple.notes.table")),
            Run(length: 2, attachment: ("i2", "com.adobe.pdf")),
            Run(length: 2, attachment: ("i3", "com.apple.paper")),
            Run(length: 2, attachment: ("i4", "public.heic")),
        ])
        #expect(result.document.blocks == [
            .image(attachmentIndex: 0),
            .table(html: "", cells: []),
            .file(attachmentIndex: 2, name: "", uti: "com.adobe.pdf"),
            .drawing(attachmentIndex: 3),
            .image(attachmentIndex: 4),
        ])
        #expect(result.attachments == [
            NoteStoreAttachment(identifier: "i0", uti: "public.jpeg"),
            NoteStoreAttachment(identifier: "i1", uti: "com.apple.notes.table"),
            NoteStoreAttachment(identifier: "i2", uti: "com.adobe.pdf"),
            NoteStoreAttachment(identifier: "i3", uti: "com.apple.paper"),
            NoteStoreAttachment(identifier: "i4", uti: "public.heic"),
        ])
    }

    @Test func dropsAttachmentCharacterWithoutInfo() throws {
        let result = try Self.decode(text: "a\u{FFFC}b\n\u{FFFC}", runs: [Run(length: 5)])
        #expect(result.document.blocks == [.paragraph([TextRun("ab")]), .paragraph([])])
        #expect(result.attachments.isEmpty)
    }

    @Test func inlineAttachmentIsKeptAsFileAfterItsLine() throws {
        let result = try Self.decode(text: "a\u{FFFC}b\n\u{FFFC}", runs: [
            Run(length: 1), Run(length: 1, attachment: ("x", "public.png")), Run(length: 2), Run(length: 1, attachment: ("y", "public.png")),
        ])
        #expect(result.document.blocks == [
            .paragraph([TextRun("ab")]), .file(attachmentIndex: 0, name: "", uti: "public.png"), .image(attachmentIndex: 1),
        ])
        #expect(result.attachments.count == 2)
    }

    @Test func inlineHashtagAttachmentIsNotHidden() throws {
        let uti = "com.apple.notes.inlinetextattachment.hashtag"
        let result = try Self.decode(text: "see \u{FFFC} now", runs: [
            Run(length: 4), Run(length: 1, attachment: ("h", uti)), Run(length: 4),
        ])
        #expect(result.document.blocks == [.paragraph([TextRun("see  now")]), .file(attachmentIndex: 0, name: "", uti: uti)])
    }

    @Test func unknownStyleTypeThrows() {
        #expect(throws: NoteStoreDecoderError.malformed("style 7")) { try Self.decode(text: "a", runs: [Run(length: 1, style: 7)]) }
    }

    @Test func minusOneStyleIsBodyText() throws {
        var writer = ProtobufWriter()
        writer.message(2) { d in
            d.message(3) { n in
                n.string(2, "a")
                n.message(5) { r in
                    r.varint(1, 1)
                    r.message(2) { p in p.varint(1, UInt64.max) }
                }
            }
        }
        #expect(try NoteStoreDecoder.decode(Self.gzip(writer.data)).document.blocks == [.paragraph([TextRun("a")])])
    }

    @Test func quoteBeatsCode() throws {
        let result = try Self.decode(text: "x", runs: [Run(length: 1, style: 4, quote: true)])
        #expect(result.document.blocks == [.quote([TextRun("x")])])
    }

    @Test func runAcrossNewlineStylesBothLines() throws {
        let result = try Self.decode(text: "ab\ncd", runs: [Run(length: 5, weight: 1)])
        #expect(result.document.blocks == [.paragraph([TextRun("ab", style: .bold)]), .paragraph([TextRun("cd", style: .bold)])])
    }

    @Test func keepsEmptyMiddleLinesAndDropsOnlyTheTrailingOne() throws {
        let result = try Self.decode(text: "a\n\nb\n", runs: [Run(length: 5)])
        #expect(result.document.blocks == [.paragraph([TextRun("a")]), .paragraph([]), .paragraph([TextRun("b")])])
    }

    @Test func textBeyondTheRunsIsPlainParagraph() throws {
        let result = try Self.decode(text: "ab\ncd", runs: [Run(length: 3, style: 100)])
        #expect(result.document.blocks == [.listItem(.bullet, indent: 0, [TextRun("ab")]), .paragraph([TextRun("cd")])])
    }

    @Test func skipsUnknownFieldsOfEveryWireType() throws {
        var data = ProtobufWriter()
        data.varint(1, 7)
        data.fixed64(4, 9)
        data.fixed32(6, 3)
        data.message(2) { document in
            document.varint(9, 1)
            document.message(3) { note in
                note.fixed64(1, 1)
                note.string(2, "hi")
                note.string(40, "ignored")
                note.message(5) { run in
                    run.varint(1, 2)
                    run.fixed32(30, 5)
                    run.string(31, "x")
                }
            }
        }
        let result = try NoteStoreDecoder.decode(Self.gzip(data.data))
        #expect(result.document.blocks == [.paragraph([TextRun("hi")])])
    }

    @Test func rejectsNonGzip() {
        #expect(throws: NoteStoreDecoderError.notGzip) { try NoteStoreDecoder.decode(Data("not gzip at all".utf8)) }
        #expect(throws: NoteStoreDecoderError.notGzip) { try NoteStoreDecoder.decode(Data()) }
    }

    @Test func truncatedGzipThrows() throws {
        let zipped = try Self.gzip(Self.protobuf(text: String(repeating: "hello ", count: 200), runs: [Run(length: 1200)]))
        for cut in [3, 10, zipped.count / 2, zipped.count - 9, zipped.count - 1] {
            #expect(throws: NoteStoreDecoderError.self) { try NoteStoreDecoder.decode(zipped.prefix(cut)) }
        }
    }

    @Test func decompressesLargeOutput() throws {
        let big = Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31 >> 3) })
        #expect(try Gzip.decompress(Self.gzip(big)) == big)
    }

    @Test func truncatedProtobufThrows() throws {
        let good = Self.protobuf(text: "hello", runs: [Run(length: 5, weight: 1)])
        for cut in 1..<good.count {
            _ = try? NoteStoreDecoder.decode(Self.gzip(good.prefix(cut)))   // must not crash
        }
        #expect(throws: NoteStoreDecoderError.self) { try NoteStoreDecoder.decode(Self.gzip(good.prefix(good.count - 1))) }
        var lengthOverrun = ProtobufWriter()
        lengthOverrun.raw([0x12, 0x7F, 0x01])   // field 2, length 127, one byte left
        #expect(throws: NoteStoreDecoderError.self) { try NoteStoreDecoder.decode(Self.gzip(lengthOverrun.data)) }
    }

    @Test func hostileProtobufThrows() throws {
        for bytes: [UInt8] in [
            [0x08] + [UInt8](repeating: 0xFF, count: 11),   // varint over 10 bytes
            [0x0B],                                          // start-group wire type
            [0x0C],                                          // end-group wire type
            [0x00, 0x01],                                    // field number 0
            [0x09, 1, 2, 3],                                 // fixed64 short
            [0x0D, 1, 2],                                    // fixed32 short
            [0x12],                                          // tag with no length
        ] {
            var writer = ProtobufWriter()
            writer.raw(bytes)
            #expect(throws: NoteStoreDecoderError.self) { try NoteStoreDecoder.decode(Self.gzip(writer.data)) }
        }
    }

    /// A huge run length after a non-empty run, and a huge indent, must not overflow (a trap kills the app).
    @Test func hugeLengthAndIndentAreClamped() throws {
        let data = Self.protobuf(text: "ab\ncd", runs: [Run(length: 1)]) { note in
            note.message(5) { r in
                r.varint(1, UInt64.max)
                r.message(2) { p in
                    p.varint(1, 100)
                    p.varint(4, UInt64(Int64.max))
                }
            }
        }
        let decoded = try NoteStoreDecoder.decode(Self.gzip(data))
        #expect(decoded.document.plainText == "ab\ncd")
        #expect(decoded.document.blocks.last == .listItem(.bullet, indent: NoteDocument.maxListIndent, [TextRun("cd")]))
    }

    @Test func writerTakesAHugeIndentAsOneLevelDeeper() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [.listItem(.bullet, indent: Int.max, [TextRun("a")])]), images: [:])
        #expect(html.hasPrefix("<ul><li>"))
    }

    /// A one-line note "ab" whose single run also carries `build`'s fields.
    static func formatted(_ build: (inout ProtobufWriter) -> Void) throws -> DecodedNote {
        var root = ProtobufWriter()
        root.message(2) { document in
            document.message(3) { note in
                note.string(2, "ab")
                note.message(5) { r in
                    r.varint(1, 2)
                    build(&r)
                }
            }
        }
        return try NoteStoreDecoder.decode(Self.gzip(root.data))
    }

    /// Font, superscript, colour, highlight and alignment cannot be written back through HTML: a save would drop them.
    @Test func flagsFormattingTheWriterCannotKeep() throws {
        let font = try Self.formatted { r in r.message(3) { f in f.string(1, "Georgia") } }
        let superscript = try Self.formatted { r in r.varint(8, 1) }
        let colour = try Self.formatted { r in r.message(10) { c in c.fixed32(1, 0x3F80_0000) } }
        let highlight = try Self.formatted { r in r.varint(14, 1) }
        let centred = try Self.formatted { r in r.message(2) { p in p.varint(2, 1) } }
        for decoded in [font, superscript, colour, highlight, centred] {
            #expect(decoded.hasUnsupportedFormatting)
            #expect(decoded.document.plainText == "ab")
        }
    }

    @Test func plainFormattingIsNotFlagged() throws {
        let plain = try Self.formatted { r in
            r.message(2) { p in
                p.varint(1, 0)
                p.varint(2, 0)    // left alignment, as Notes writes for a title
                p.varint(3, 1)    // present on most real paragraphs
            }
            r.varint(5, 3)
            r.varint(6, 1)
            r.varint(7, 1)
            r.varint(8, 0)
        }
        #expect(!plain.hasUnsupportedFormatting)
    }

    @Test func readerWalksAllWireTypes() throws {
        var writer = ProtobufWriter()
        writer.varint(1, 300)
        writer.bytes(2, Data([1, 2]))
        writer.fixed32(3, 5)
        writer.fixed64(4, 6)
        var reader = ProtobufReader(writer.data)
        let first = try #require(try reader.next())
        #expect(first.field == 1)
        guard case .varint(300) = first.value else { Issue.record("varint"); return }
        guard case .bytes(let b)? = try reader.next()?.value, b == Data([1, 2]) else { Issue.record("bytes"); return }
        guard case .fixed32(5)? = try reader.next()?.value else { Issue.record("fixed32"); return }
        guard case .fixed64(6)? = try reader.next()?.value else { Issue.record("fixed64"); return }
        #expect(try reader.next() == nil)
    }

    @Test func missingNoteMessageThrows() throws {
        var root = ProtobufWriter()
        root.varint(1, 1)
        #expect(throws: NoteStoreDecoderError.malformed("no note")) { try NoteStoreDecoder.decode(Self.gzip(root.data)) }
    }

    @Test func presentNoteWithEmptyTextIsEmptyDocument() throws {
        let result = try Self.decode(text: "", runs: [])
        #expect(result.document.blocks.isEmpty)
    }

    /// A note made by hand in Notes on macOS 27: title, a checklist with the first item done, a numbered list,
    /// a quote and a picture.
    @Test func decodesRealNoteFromMacOS27() throws {
        let data = try Data(contentsOf: #require(Bundle.module.url(forResource: "Fixtures/real-macos27", withExtension: "notedata")))
        let result = try NoteStoreDecoder.decode(data)
        // Notes moves a done item below the others.
        #expect(result.document.blocks == [
            .heading(level: 1, [TextRun("Mẫu thử AraNotch", style: .bold)]),
            .listItem(.checklist(done: false), indent: 0, [TextRun("Việc hai")]),
            .listItem(.checklist(done: true), indent: 0, [TextRun("Việc một")]),
            .listItem(.numbered, indent: 0, [TextRun("Số một")]),
            .listItem(.numbered, indent: 0, [TextRun("Số hai")]),
            .quote([TextRun("Câu trích dẫn")]),
            .paragraph([]),
            .paragraph([]),
            .image(attachmentIndex: 0),
        ])
        #expect(result.attachments == [NoteStoreAttachment(identifier: "9A3CCEDB-3080-404F-875A-A3C58E3006F5", uti: "public.png")])
        #expect(!result.hasUnsupportedFormatting)
    }

    static func real(_ name: String) throws -> DecodedNote {
        try NoteStoreDecoder.decode(Data(contentsOf: #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "notedata"))))
    }

    /// Notes made through HTML on macOS 27 carry a font with a size, and Courier, .AppleSystemUIFont or
    /// .AppleSystemUIFontBold as its name: that is AraNotch's own formatting, not something a save drops.
    @Test func realNotesWrittenThroughHTMLAreNotFlagged() throws {
        #expect(try !Self.real("real-html-written").hasUnsupportedFormatting)
        #expect(try !Self.real("real-html-headings").hasUnsupportedFormatting)
        #expect(try !Self.real("real-macos27").hasUnsupportedFormatting)
    }

    @Test func realColouredWordIsFlagged() throws {
        #expect(try Self.real("real-html-colour").hasUnsupportedFormatting)
    }

    /// Each block as its kind and text, with headings' levels: what a save would write back.
    static func outline(_ name: String) throws -> [String] {
        try real(name).document.blocks.map { block in
            switch block {
            case .heading(let level, let runs): "h\(level) " + runs.map(\.text).joined()
            case .paragraph(let runs): "p " + runs.map(\.text).joined()
            case .code(let text): "code " + text
            default: "other"
            }
        }
    }

    /// The database keeps the sizes the HTML gives; headings must read back as headings there too, or the next
    /// save writes them at body size. Real notes: AraNotch's bold 24/21/18 form, and Notes' h1–h3 form.
    @Test func realHeadingsReadAsHeadingsFromTheDatabase() throws {
        #expect(try Self.outline("real-araNotch-headings") == [
            "h1 H1 title", "h2 H2 head", "h3 H3 sub", "p body text 80", "h2 H2 it mid", "p end",
        ])
        #expect(try Self.outline("real-html-headings") == [
            "h1 H1 title", "h2 H2 head", "p H3 sub", "p body text 80", "p H2 it mid", "p end",
        ])
    }

    @Test func courierIsMonospaced() throws {
        #expect(try Self.outline("real-html-written").contains("code x"))
        let runs = try Self.real("real-inline-courier").document.blocks.flatMap { block -> [TextRun] in
            if case .paragraph(let runs) = block { return runs } else { return [] }
        }
        #expect(runs.contains(TextRun("mono", style: .monospaced)))
        #expect(runs.contains(TextRun("bold", style: .bold)))
    }
}
