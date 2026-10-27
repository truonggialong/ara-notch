import Foundation
import Testing
@testable import NotesCore

@Suite struct NotesHTMLReaderTests {
    /// The note read from Notes in the 2026-10-27 probe (see Modules/Notes/DESIGN.md).
    static func probe() throws -> NoteDocument {
        let html = try String(contentsOf: #require(Bundle.module.url(forResource: "Fixtures/probe-read", withExtension: "html")), encoding: .utf8)
        let plain = try String(contentsOf: #require(Bundle.module.url(forResource: "Fixtures/probe-plaintext", withExtension: "txt")), encoding: .utf8)
        return NotesHTMLReader.read(html: html, plainText: plain)
    }

    @Test func readsInlineStylesFromProbe() throws {
        let document = try Self.probe()
        #expect(document.blocks[3] == .paragraph([
            TextRun("bold", style: .bold), TextRun(" "),
            TextRun("italic", style: .italic), TextRun(" "),
            TextRun("under", style: .underline), TextRun(" "),
            TextRun("strike", style: .strikethrough), TextRun(" "),
            TextRun("mono", style: .monospaced), TextRun(" "),
            TextRun("link", link: URL(string: "https://example.com/")),
        ]))
    }

    @Test func readsHeadingsWrittenAsBoldSizes() throws {
        let document = try Self.probe()
        #expect(document.blocks[0] == .heading(level: 1, [TextRun("Probe title", style: .bold)]))
        #expect(document.blocks[1] == .heading(level: 2, [TextRun("Heading", style: .bold)]))
        #expect(document.blocks[2] == .paragraph([TextRun("Sub", style: .bold)]))
    }

    @Test func readsNativeHeadingTags() {
        let document = NotesHTMLReader.read(html: "<div><h1>Tiêu đề</h1></div>", plainText: "Tiêu đề")
        #expect(document.blocks == [.heading(level: 1, [TextRun("Tiêu đề")])])
        let probe = try? Self.probe()
        #expect(probe?.blocks[10] == .heading(level: 1, [TextRun("Tiêu đề")]))
        #expect(probe?.blocks[11] == .heading(level: 2, [TextRun("Đề mục")]))
    }

    @Test func placesImageAtObjectReplacementLine() throws {
        let blocks = try Self.probe().blocks
        let images = blocks.enumerated().filter { if case .image = $0.element { true } else { false } }
        #expect(images.count == 1)
        #expect(images[0].element == .image(attachmentIndex: 0))
        #expect(blocks[images[0].offset - 1] == .code("code block"))
        #expect(blocks[images[0].offset + 1] == .paragraph([TextRun("end edited")]))
    }

    @Test func keepsTableHTMLVerbatim() throws {
        let blocks = try Self.probe().blocks
        guard case .table(let html, let cells) = blocks.last else {
            Issue.record("last block is not a table")
            return
        }
        #expect(html.hasPrefix("<object><table"))
        #expect(html.hasSuffix("</table></object>"))
        #expect(cells == [["Cột 1", "Cột 2"], ["", ""]])
    }

    @Test func decodesEntitiesAndVietnamese() {
        let document = NotesHTMLReader.read(html: "<div>A &amp; B &lt;c&gt; Tiếng Việt 😀 &#39;x&#39; &quot;y&quot;&nbsp;&#128512;</div>",
                                            plainText: "")
        #expect(document.blocks == [.paragraph([TextRun("A & B <c> Tiếng Việt 😀 'x' \"y\"\u{A0}😀")])])
    }

    @Test func dashListIsDash() throws {
        let blocks = try Self.probe().blocks
        #expect(blocks.contains(.listItem(.dash, indent: 0, [TextRun("Đơn cách")])))
    }

    @Test func plainListIsBulletAndOrderedIsNumbered() {
        let html = "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul><ol><li>d</li></ol>"
        let document = NotesHTMLReader.read(html: html, plainText: "a\nb\nc\nd")
        #expect(document.blocks == [
            .listItem(.bullet, indent: 0, [TextRun("a")]),
            .listItem(.bullet, indent: 1, [TextRun("b")]),
            .listItem(.bullet, indent: 0, [TextRun("c")]),
            .listItem(.numbered, indent: 0, [TextRun("d")]),
        ])
    }

    @Test func plainDivsAndEmptyParagraphs() throws {
        let blocks = try Self.probe().blocks
        #expect(blocks[6] == .paragraph([TextRun("quote")]))
        #expect(blocks[16] == .paragraph([TextRun("Trích dẫn")]))
        #expect(blocks[17] == .paragraph([]))
    }

    @Test func mergesAdjacentRunsAndDropsEmptyOnes() {
        let html = "<div><b>a</b><b>b</b><i></i><span> </span><b>c</b></div>"
        let document = NotesHTMLReader.read(html: html, plainText: "ab c")
        #expect(document.blocks == [.paragraph([TextRun("ab", style: .bold), TextRun(" "), TextRun("c", style: .bold)])])
    }

    @Test func linkIsNotUnderlinedByNotesWrapper() {
        let html = "<div><u><a href=\"https://a.b/?x=1&amp;y=2\">go</a></u><u>kept</u></div>"
        let document = NotesHTMLReader.read(html: html, plainText: "gokept")
        #expect(document.blocks == [.paragraph([TextRun("go", link: URL(string: "https://a.b/?x=1&y=2")),
                                                TextRun("kept", style: .underline)])])
    }

    @Test func readsHeadingLevelThreeFromBoldThirteen() {
        let html = "<div><b><font face=\".AppleSystemUIFontBold\"><span style=\"font-size: 13px\">S</span></font></b></div>"
        #expect(NotesHTMLReader.read(html: html, plainText: "S").blocks == [.heading(level: 3, [TextRun("S", style: .bold)])])
    }

    @Test func imageDivStaysEmptyParagraphWithoutPlaceholderLine() {
        let html = "<div><br></div><div><span><br></span><span><br></span></div>"
        let document = NotesHTMLReader.read(html: html, plainText: "\n\u{FFFC}")
        #expect(document.blocks == [.paragraph([]), .image(attachmentIndex: 0)])
    }
}
