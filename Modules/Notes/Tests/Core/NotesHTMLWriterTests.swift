import Foundation
import Testing
@testable import NotesCore

@Suite struct NotesHTMLWriterTests {
    static let png = NoteImageData(data: Data([1, 2, 3, 4]), mimeType: "image/png")
    static let table = "<object><table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table></object>"

    /// What Notes on macOS 27 keeps of the sizes AraNotch writes (seen 2026-10-27). It drops `white-space: pre-wrap`
    /// and returns the spaces and tabs it kept raw inside `<span style="font-size: 15px">`.
    static func keptByNotes(_ html: String) -> String {
        let kept = [28: 24, 24: 21, 21: 18, 18: 15]
        var result = ""
        var rest = Substring(html.replacingOccurrences(of: "; white-space: pre-wrap", with: ""))
        while let range = rest.range(of: "font-size: ") {
            result += rest[..<range.upperBound]
            rest = rest[range.upperBound...]
            let digits = rest.prefix(while: \.isNumber)
            result += String(Int(digits).flatMap { kept[$0] } ?? Int(digits) ?? 0)
            rest = rest.dropFirst(digits.count)
        }
        return result + rest
    }

    @Test func roundTripsEveryWritableBlock() throws {
        let document = NoteDocument(blocks: [
            .heading(level: 1, [TextRun("Title", style: .bold)]),
            .heading(level: 2, [TextRun("Heading", style: .bold)]),
            .heading(level: 3, [TextRun("Sub", style: .bold)]),
            .paragraph([
                TextRun("plain "), TextRun("bold", style: .bold), TextRun(" "),
                TextRun("it", style: [.italic, .underline]), TextRun(" "),
                TextRun("gone", style: .strikethrough), TextRun(" "),
                TextRun("mono", style: .monospaced), TextRun(" "),
                TextRun("link", style: .underline, link: URL(string: "https://example.com/?a=1&b=2")),
                TextRun(" end"),
            ]),
            .paragraph([]),
            .paragraph([TextRun("a<b>&\"q\"")]),
            .listItem(.bullet, indent: 0, [TextRun("one")]),
            .listItem(.bullet, indent: 1, [TextRun("nested")]),
            .listItem(.bullet, indent: 2, [TextRun("deeper")]),
            .listItem(.bullet, indent: 0, [TextRun("two")]),
            .listItem(.dash, indent: 0, [TextRun("dash")]),
            .listItem(.dash, indent: 1, [TextRun("dash nested")]),
            .paragraph([TextRun("between")]),
            .code("let x = 1"),
            .image(attachmentIndex: 0),
            .table(html: Self.table, cells: [["A", "B"], ["C", "D"]]),
            .image(attachmentIndex: 2),
            .paragraph([TextRun("last")]),
        ])
        let html = try NotesHTMLWriter.write(document, images: [0: Self.png, 2: Self.png])
        let back = NotesHTMLReader.read(html: Self.keptByNotes(html), plainText: document.plainText)
        #expect(back == document)
    }

    @Test func roundTripsMultiLineCodeAsOneBlock() throws {
        let document = NoteDocument(blocks: [.code("a\n  b\nc"), .paragraph([TextRun("x")])])
        let html = try NotesHTMLWriter.write(document, images: [:])
        #expect(html.contains("a<br>"))
        #expect(NotesHTMLReader.read(html: Self.keptByNotes(html), plainText: "a\n  b\nc\nx") == document)
    }

    @Test func writesHeadingsAsAraNotchForms() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [
            .heading(level: 1, [TextRun("T")]), .heading(level: 3, [TextRun("S")]),
        ]), images: [:])
        #expect(html.contains("<div><b><span style=\"font-size: 28px; white-space: pre-wrap\">T</span></b></div>"))
        #expect(html.contains("<div><b><span style=\"font-size: 21px; white-space: pre-wrap\">S</span></b></div>"))
    }

    /// Below 18 px Notes shows text at 11 px, smaller than its own.
    @Test func writesBodyTextAtEighteenPixels() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [
            .paragraph([TextRun("p")]), .paragraph([]), .listItem(.bullet, indent: 0, [TextRun("i")]), .code("c"),
        ]), images: [:])
        let span = "<span style=\"font-size: 18px; white-space: pre-wrap\">"
        #expect(html == "<div>\(span)p</span></div><div>\(span)<br></span></div>"
            + "<ul><li>\(span)i</span></li></ul>"
            + "<div><font face=\"Courier\">\(span)c</span></font></div>")
    }

    /// Notes collapses runs of spaces and drops tabs and leading spaces from HTML, unless the span says
    /// `white-space: pre-wrap` (checked on Notes 2026-10-27).
    @Test func keepsLeadingSpacesRunsAndTabs() throws {
        let document = NoteDocument(blocks: [
            .paragraph([TextRun("  lead  two\ttab")]),
            .listItem(.bullet, indent: 0, [TextRun("  item\tx")]),
            .heading(level: 2, [TextRun("  H  1", style: .bold)]),
        ])
        let html = try NotesHTMLWriter.write(document, images: [:])
        #expect(html.components(separatedBy: "white-space: pre-wrap").count == 4)
        #expect(NotesHTMLReader.read(html: Self.keptByNotes(html), plainText: document.plainText) == document)
    }

    @Test func keepsTheIndentationOfACodeBlock() throws {
        let document = NoteDocument(blocks: [.code("func f() {\n    return 1\n\tdone\n}"), .paragraph([TextRun("x")])])
        let html = try NotesHTMLWriter.write(document, images: [:])
        #expect(html.contains("<font face=\"Courier\"><span style=\"font-size: 18px; white-space: pre-wrap\">"))
        #expect(NotesHTMLReader.read(html: Self.keptByNotes(html), plainText: document.plainText) == document)
    }

    @Test func groupsListItemsAndMarksDashLists() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [
            .listItem(.bullet, indent: 0, [TextRun("a")]), .listItem(.bullet, indent: 0, [TextRun("b")]),
            .listItem(.dash, indent: 0, [TextRun("c")]),
        ]), images: [:])
        #expect(html.components(separatedBy: "<ul>").count == 2)
        #expect(html.contains("<ul class=\"Apple-dash-list\">"))
    }

    @Test func embedsEveryImageInOrder() throws {
        let one = NoteImageData(data: Data([0xAA]), mimeType: "image/png")
        let two = NoteImageData(data: Data([0xBB]), mimeType: "")
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [
            .image(attachmentIndex: 0), .image(attachmentIndex: 1),
        ]), images: [0: one, 1: two])
        let marker = "<img src=\"data:image/png;base64,"
        #expect(html.components(separatedBy: marker).count == 3)
        let first = html.range(of: marker + "qg==")
        let second = html.range(of: marker + "uw==")
        #expect(first != nil && second != nil && first!.lowerBound < second!.lowerBound)
    }

    @Test func refusesToWriteWithAMissingImage() {
        let document = NoteDocument(blocks: [.image(attachmentIndex: 0), .image(attachmentIndex: 1)])
        #expect(throws: NotesHTMLWriterError.missingImage(1)) {
            try NotesHTMLWriter.write(document, images: [0: Self.png])
        }
    }

    @Test func refusesBlocksItCannotWrite() {
        let cases: [(NoteBlock, String)] = [
            (.listItem(.checklist(done: false), indent: 0, []), "checklist"),
            (.listItem(.numbered, indent: 0, []), "numberedList"),
            (.quote([]), "quote"),
            (.file(attachmentIndex: 0, name: "a", uti: "public.data"), "file"),
            (.drawing(attachmentIndex: 0), "drawing"),
            (.table(html: "", cells: []), "table"),
        ]
        for (block, kind) in cases {
            #expect(throws: NotesHTMLWriterError.unwritableBlock(kind)) {
                try NotesHTMLWriter.write(NoteDocument(blocks: [block]), images: [:])
            }
        }
    }

    @Test func escapesMarkup() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [.paragraph([TextRun("a<b>&")])]), images: [:])
        #expect(html.contains("a&lt;b&gt;&amp;"))
    }

    @Test func refusesAnImageWithEmptyData() {
        let document = NoteDocument(blocks: [.image(attachmentIndex: 0)])
        #expect(throws: NotesHTMLWriterError.missingImage(0)) {
            try NotesHTMLWriter.write(document, images: [0: NoteImageData(data: Data(), mimeType: "image/png")])
        }
    }

    @Test func treatsANegativeIndentAsTopLevel() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [
            .listItem(.bullet, indent: -1, [TextRun("a")]), .listItem(.bullet, indent: -3, [TextRun("b")]),
        ]), images: [:])
        let span = "<span style=\"font-size: 18px; white-space: pre-wrap\">"
        #expect(html == "<ul><li>\(span)a</span></li><li>\(span)b</span></li></ul>")
    }
}
