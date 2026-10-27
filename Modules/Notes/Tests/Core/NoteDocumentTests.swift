import Foundation
import Testing
@testable import NotesCore

@Suite struct NoteDocumentTests {
    @Test func plainTextJoinsBlocksWithObjectReplacementForImages() {
        let document = NoteDocument(blocks: [
            .paragraph([TextRun("Chào")]),
            .image(attachmentIndex: 0),
            .listItem(.bullet, indent: 0, [TextRun("a")]),
        ])
        #expect(document.plainText == "Chào\n\u{FFFC}\na")
        #expect(document.imageCount == 1)
    }

    @Test func everyAttachmentBlockIsOneObjectReplacement() {
        let document = NoteDocument(blocks: [
            .table(html: "<table></table>", cells: [["a"]]),
            .file(attachmentIndex: 1, name: "a.pdf", uti: "com.adobe.pdf"),
            .drawing(attachmentIndex: 2),
        ])
        #expect(document.plainText == "\u{FFFC}\n\u{FFFC}\n\u{FFFC}")
        #expect(document.imageCount == 0)
    }

    @Test func textBlocksUseTheirRunsAndCodeKeepsItsText() {
        let document = NoteDocument(blocks: [
            .heading(level: 1, [TextRun("A", style: .bold), TextRun("B")]),
            .quote([TextRun("q")]),
            .code("x = 1"),
        ])
        #expect(document.plainText == "AB\nq\nx = 1")
    }
}
