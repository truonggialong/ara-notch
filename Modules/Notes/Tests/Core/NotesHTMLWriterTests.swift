import Foundation
import Testing
@testable import NotesCore

@Suite struct NotesHTMLWriterTests {
    static let png = NoteImageData(data: Data([1, 2, 3, 4]), mimeType: "image/png")
    static let table = "<object><table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table></object>"

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
        let back = NotesHTMLReader.read(html: html, plainText: document.plainText)
        #expect(back == document)
    }

    @Test func roundTripsMultiLineCodeAsOneBlock() throws {
        let document = NoteDocument(blocks: [.code("a\n  b\nc"), .paragraph([TextRun("x")])])
        let html = try NotesHTMLWriter.write(document, images: [:])
        #expect(html.contains("a<br>"))
        #expect(NotesHTMLReader.read(html: html, plainText: "a\n  b\nc\nx") == document)
    }

    @Test func writesHeadingsAsAraNotchForms() throws {
        let html = try NotesHTMLWriter.write(NoteDocument(blocks: [
            .heading(level: 1, [TextRun("T")]), .heading(level: 3, [TextRun("S")]),
        ]), images: [:])
        #expect(html.contains("<div><b><font face=\".AppleSystemUIFontBold\"><span style=\"font-size: 21px\">T</span></font></b></div>"))
        #expect(html.contains("font-size: 13px\">S</span>"))
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
}
