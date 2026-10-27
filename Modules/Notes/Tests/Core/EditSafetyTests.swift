import Foundation
import Testing
@testable import NotesCore

@Suite struct EditSafetyTests {
    static func p(_ s: String) -> NoteBlock { .paragraph([TextRun(s)]) }

    /// Checks a document against its own plain text, so only the block rules are under test.
    static func check(full: NoteDocument?, html: NoteDocument? = nil, locked: Bool = false) -> EditSafety {
        let html = html ?? full ?? NoteDocument(blocks: [])
        return EditSafety.check(full: full, html: html, isLocked: locked, plainText: (full ?? html).plainText)
    }

    @Test func checklistMakesReadOnly() {
        let doc = NoteDocument(blocks: [.listItem(.checklist(done: false), indent: 0, [TextRun("x")])])
        #expect(Self.check(full: doc) == .readOnly([.checklist]))
    }

    @Test func numberedAndQuoteListBothReasons() {
        let doc = NoteDocument(blocks: [
            .quote([TextRun("q")]),
            .listItem(.numbered, indent: 0, [TextRun("n")]),
            .listItem(.numbered, indent: 0, [TextRun("m")]),
        ])
        #expect(Self.check(full: doc) == .readOnly([.numberedList, .quote]))
    }

    @Test func fileAndDrawingGiveReasons() {
        let doc = NoteDocument(blocks: [
            .drawing(attachmentIndex: 1), .file(attachmentIndex: 0, name: "a", uti: "public.data"),
        ])
        #expect(Self.check(full: doc) == .readOnly([.file, .drawing]))
    }

    @Test func imagesTablesHeadingsStayEditable() {
        let doc = NoteDocument(blocks: [
            .heading(level: 1, [TextRun("T")]), .image(attachmentIndex: 0),
            .table(html: "<table></table>", cells: [["a"]]),
            .listItem(.bullet, indent: 0, [TextRun("b")]), .code("c"),
        ])
        #expect(Self.check(full: doc) == .editable)
    }

    @Test func withoutDatabaseAnyBulletIsReadOnly() {
        let doc = NoteDocument(blocks: [.listItem(.bullet, indent: 0, [TextRun("b")])])
        #expect(Self.check(full: nil, html: doc) == .readOnly([.listsUnknown]))
    }

    @Test func withoutDatabasePlainTextIsEditable() {
        let doc = NoteDocument(blocks: [Self.p("a"), .image(attachmentIndex: 0)])
        #expect(Self.check(full: nil, html: doc) == .editable)
    }

    @Test func lockedIsReadOnly() {
        let doc = NoteDocument(blocks: [.quote([TextRun("q")])])
        let safety = EditSafety.check(full: doc, html: doc, isLocked: true, plainText: "different")
        #expect(safety == .readOnly([.locked]))
    }

    @Test func textMismatchIsUnreadable() {
        let doc = NoteDocument(blocks: [Self.p("a"), Self.p("b")])
        let safety = EditSafety.check(full: nil, html: doc, isLocked: false, plainText: "a\nb\nc")
        #expect(safety == .readOnly([.unreadable]))
    }

    @Test func unreadableComesLastAmongReasons() {
        let doc = NoteDocument(blocks: [.quote([TextRun("q")])])
        let safety = EditSafety.check(full: doc, html: doc, isLocked: false, plainText: "other")
        #expect(safety == .readOnly([.quote, .unreadable]))
    }

    @Test func fullDocumentIsTheOneCompared() {
        let full = NoteDocument(blocks: [Self.p("a"), Self.p("b")])
        let html = NoteDocument(blocks: [Self.p("a")])
        #expect(EditSafety.check(full: full, html: html, isLocked: false, plainText: "a\nb") == .editable)
    }

    @Test func normalisationIgnoresCRLFAndTrailingSpace() {
        #expect(EditSafety.normalise("a \r\nb\n\n") == EditSafety.normalise("a\nb"))
        #expect(EditSafety.normalise("a\u{2028}b\u{2029}c\rd\t") == "a\nb\nc\nd")
        #expect(EditSafety.normalise("a\n\nb") != EditSafety.normalise("a\nb"))
        let doc = NoteDocument(blocks: [Self.p("a"), Self.p("b")])
        #expect(EditSafety.check(full: nil, html: doc, isLocked: false, plainText: "a \r\nb\n\n") == .editable)
    }

    @Test func attachmentMarkersMustLineUp() {
        let doc = NoteDocument(blocks: [Self.p("a"), .image(attachmentIndex: 0)])
        let safety = EditSafety.check(full: nil, html: doc, isLocked: false, plainText: "\u{FFFC}\na")
        #expect(safety == .readOnly([.unreadable]))
    }

    @Test func htmlOnlyQuoteIsReadOnly() {
        let doc = NoteDocument(blocks: [.quote([TextRun("q")])])
        #expect(Self.check(full: nil, html: doc) == .readOnly([.quote]))
    }

    @Test func htmlOnlyFileIsReadOnly() {
        let doc = NoteDocument(blocks: [.file(attachmentIndex: 0, name: "a", uti: "public.data")])
        #expect(Self.check(full: nil, html: doc) == .readOnly([.file]))
    }

    @Test func tableLineHasOneAttachmentMarker() {
        let doc = NoteDocument(blocks: [Self.p("before"), .table(html: "<table></table>", cells: [["a"]]), Self.p("after")])
        let safety = EditSafety.check(full: nil, html: doc, isLocked: false, plainText: "before\n\u{FFFC}\nafter\n\n")
        #expect(safety == .editable)
    }

    @Test func sameSecondWrites() {
        let t = Date(timeIntervalSince1970: 1000)
        #expect(SaveGuard.decide(openedAt: t, currentModification: t) == .write)
        #expect(SaveGuard.decide(openedAt: t, currentModification: t.addingTimeInterval(1)) == .write)
    }

    @Test func laterModificationConflicts() {
        let t = Date(timeIntervalSince1970: 1000)
        #expect(SaveGuard.decide(openedAt: t, currentModification: t.addingTimeInterval(1.5)) == .conflict)
        #expect(SaveGuard.decide(openedAt: t, currentModification: t.addingTimeInterval(-5)) == .conflict)
    }
}
