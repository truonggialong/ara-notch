import AppKit
import Foundation
import Testing
import NotesCore
@testable import NotesFeature

@MainActor private func storage(_ doc: NoteDocument) -> NSTextStorage {
    NSTextStorage(attributedString: NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail))
}

@MainActor private func roundTrip(_ doc: NoteDocument, images: [Int: NSImage] = [:]) -> NoteDocument {
    NoteAttributedText.document(from: NoteAttributedText.make(doc, images: images, imageSize: .thumbnail), original: doc)
}

private let sample = NoteDocument(blocks: [
    .heading(level: 1, [TextRun("Title")]),
    .heading(level: 2, [TextRun("Heading")]),
    .heading(level: 3, [TextRun("Sub")]),
    .paragraph([TextRun("plain "), TextRun("bold", style: .bold), TextRun(" "), TextRun("both", style: [.bold, .italic]),
                TextRun(" "), TextRun("u", style: .underline), TextRun("s", style: .strikethrough),
                TextRun("m", style: .monospaced), TextRun("link", link: URL(string: "https://example.com")!)]),
    .listItem(.bullet, indent: 0, [TextRun("one")]),
    .listItem(.bullet, indent: 1, [TextRun("nested")]),
    .listItem(.dash, indent: 0, [TextRun("dash")]),
    .listItem(.numbered, indent: 0, [TextRun("first")]),
    .listItem(.numbered, indent: 0, [TextRun("second")]),
    .listItem(.checklist(done: true), indent: 0, [TextRun("done")]),
    .listItem(.checklist(done: false), indent: 0, []),
    .quote([TextRun("quoted")]),
    .code("let a = 1\nlet b = 2"),
    .image(attachmentIndex: 0),
    .table(html: "<table><tr><td>a</td></tr></table>", cells: [["a", "b"], ["c", "d"]]),
    .file(attachmentIndex: 1, name: "report.pdf", uti: "com.adobe.pdf"),
    .drawing(attachmentIndex: 2),
    .paragraph([]),
    .paragraph([TextRun("end")]),
])

@Test @MainActor func roundTripsThroughAttributedString() {
    #expect(roundTrip(sample) == sample)
}

@Test @MainActor func roundTripKeepsImageWithItsPicture() {
    let img = NSImage(size: NSSize(width: 200, height: 100))
    #expect(roundTrip(sample, images: [0: img]) == sample)
}

@Test @MainActor func thumbnailAndFitWidthScaleImages() {
    let doc = NoteDocument(blocks: [.image(attachmentIndex: 0)])
    let img = NSImage(size: NSSize(width: 400, height: 200))
    let thumb = NoteAttributedText.make(doc, images: [0: img], imageSize: .thumbnail)
    let a = thumb.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
    #expect(a?.bounds.height == 64)
    #expect(a?.bounds.width == 128)
    let fit = NoteAttributedText.make(doc, images: [0: img], imageSize: .fitWidth(100))
    #expect((fit.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.bounds.size == NSSize(width: 100, height: 50))
    let big = NoteAttributedText.make(doc, images: [0: img], imageSize: .fitWidth(1000))
    #expect((big.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.bounds.width == 400)
}

@Test @MainActor func boldTogglesOnAndOff() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("hello world")])]))
    let range = NSRange(location: 0, length: 5)
    #expect(!NoteFormatting.isActive(.bold, in: text, range: range))
    NoteFormatting.apply(.bold, to: text, range: range, link: nil)
    #expect(NoteFormatting.isActive(.bold, in: text, range: range))
    #expect(!NoteFormatting.isActive(.bold, in: text, range: NSRange(location: 0, length: 11)))
    NoteFormatting.apply(.bold, to: text, range: range, link: nil)
    #expect(!NoteFormatting.isActive(.bold, in: text, range: range))
}

@Test @MainActor func boldOnMixedRangeMakesAllBold() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("ab", style: .bold), TextRun("cd")])]))
    let all = NSRange(location: 0, length: 4)
    NoteFormatting.apply(.bold, to: text, range: all, link: nil)
    #expect(NoteFormatting.isActive(.bold, in: text, range: all))
}

@Test @MainActor func italicCombinesWithBold() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("abc")])]))
    let all = NSRange(location: 0, length: 3)
    NoteFormatting.apply(.bold, to: text, range: all, link: nil)
    NoteFormatting.apply(.italic, to: text, range: all, link: nil)
    let doc = NoteAttributedText.document(from: text, original: NoteDocument(blocks: []))
    #expect(doc.blocks == [.paragraph([TextRun("abc", style: [.bold, .italic])])])
}

@Test @MainActor func underlineStrikeMonospaceAndLinkRoundTripThroughCommands() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("abcd")])]))
    NoteFormatting.apply(.underline, to: text, range: NSRange(location: 0, length: 1), link: nil)
    NoteFormatting.apply(.strikethrough, to: text, range: NSRange(location: 1, length: 1), link: nil)
    NoteFormatting.apply(.monospaced, to: text, range: NSRange(location: 2, length: 1), link: nil)
    let url = URL(string: "https://example.org")!
    NoteFormatting.apply(.link, to: text, range: NSRange(location: 3, length: 1), link: url)
    let doc = NoteAttributedText.document(from: text, original: NoteDocument(blocks: []))
    #expect(doc.blocks == [.paragraph([TextRun("a", style: .underline), TextRun("b", style: .strikethrough),
                                       TextRun("c", style: .monospaced), TextRun("d", link: url)])])
    NoteFormatting.apply(.link, to: text, range: NSRange(location: 3, length: 1), link: nil)
    #expect(!NoteFormatting.isActive(.link, in: text, range: NSRange(location: 3, length: 1)))
}

@Test @MainActor func clearRemovesEveryInlineStyle() {
    let url = URL(string: "https://example.com")!
    let styled = NoteDocument(blocks: [.paragraph([TextRun("abc", style: [.bold, .italic, .underline, .strikethrough, .monospaced], link: url)])])
    let text = storage(styled)
    NoteFormatting.apply(.clear, to: text, range: NSRange(location: 0, length: 3), link: nil)
    let doc = NoteAttributedText.document(from: text, original: styled)
    #expect(doc.blocks == [.paragraph([TextRun("abc")])])
}

@Test @MainActor func clearKeepsTheBlockKind() {
    let text = storage(NoteDocument(blocks: [.heading(level: 2, [TextRun("Head", style: .underline)])]))
    NoteFormatting.apply(.clear, to: text, range: NSRange(location: 0, length: 4), link: nil)
    let doc = NoteAttributedText.document(from: text, original: NoteDocument(blocks: []))
    #expect(doc.blocks == [.heading(level: 2, [TextRun("Head")])])
}

@Test @MainActor func typingAfterImageKeepsImageIndex() {
    let doc = NoteDocument(blocks: [.image(attachmentIndex: 0)])
    let text = NSMutableAttributedString(attributedString: NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail))
    // The text view hands typed text the attributes of the character before it.
    let inherited = text.attributes(at: 0, effectiveRange: nil).filter { $0.key != .attachment }
    text.append(NSAttributedString(string: "abc", attributes: inherited))
    let back = NoteAttributedText.document(from: text, original: doc)
    #expect(back.blocks == [.image(attachmentIndex: 0), .paragraph([TextRun("abc")])])
}

@Test @MainActor func newImagesNotInOriginalAreKept() {
    let doc = NoteDocument(blocks: [.image(attachmentIndex: 7)])
    let text = NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail)
    #expect(NoteAttributedText.document(from: text, original: NoteDocument(blocks: [])).blocks == [.image(attachmentIndex: 7)])
}

@Test @MainActor func checklistRendersDoneMark() {
    let doc = NoteDocument(blocks: [.listItem(.checklist(done: true), indent: 0, [TextRun("x")]),
                                    .listItem(.checklist(done: false), indent: 0, [TextRun("y")])])
    let text = NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail)
    #expect(text.string.contains("☑"))
    #expect(text.string.contains("☐"))
}

@Test @MainActor func numberedItemsCountAtTheirOwnIndent() {
    let doc = NoteDocument(blocks: [.listItem(.numbered, indent: 0, [TextRun("a")]),
                                    .listItem(.numbered, indent: 1, [TextRun("b")]),
                                    .listItem(.numbered, indent: 1, [TextRun("c")]),
                                    .listItem(.numbered, indent: 0, [TextRun("d")])])
    let text = NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail)
    #expect(text.string == "1. a\n1. b\n2. c\n2. d")
}

@Test @MainActor func emptyDocumentIsAnEmptyString() {
    let text = NoteAttributedText.make(NoteDocument(blocks: []), images: [:], imageSize: .thumbnail)
    #expect(text.length == 0)
    #expect(NoteAttributedText.document(from: text, original: NoteDocument(blocks: [])).blocks.isEmpty)
    #expect(NoteAttributedText.typingAttributes(for: .paragraph)[NoteAttribute.block] as? String == "paragraph")
}

@Test @MainActor func blockFormatsChangeEveryTouchedParagraph() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("one")]), .paragraph([TextRun("two")]), .paragraph([TextRun("three")])]))
    NoteFormatting.apply(BlockFormat.heading, to: text, range: NSRange(location: 2, length: 5))
    let doc = NoteAttributedText.document(from: text, original: NoteDocument(blocks: []))
    #expect(doc.blocks == [.heading(level: 2, [TextRun("one")]), .heading(level: 2, [TextRun("two")]), .paragraph([TextRun("three")])])
    NoteFormatting.apply(BlockFormat.body, to: text, range: NSRange(location: 0, length: 3))
    #expect(NoteAttributedText.document(from: text, original: NoteDocument(blocks: [])).blocks.first == .paragraph([TextRun("one")]))
}

@Test @MainActor func bulletListTogglesBackAndForth() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("one")]), .paragraph([TextRun("two")])]))
    let orig = NoteDocument(blocks: [])
    NoteFormatting.apply(BlockFormat.bulletList, to: text, range: NSRange(location: 0, length: text.length))
    #expect(text.string == "• one\n• two")
    #expect(NoteAttributedText.document(from: text, original: orig).blocks
            == [.listItem(.bullet, indent: 0, [TextRun("one")]), .listItem(.bullet, indent: 0, [TextRun("two")])])
    NoteFormatting.apply(BlockFormat.bulletList, to: text, range: NSRange(location: 0, length: text.length))
    #expect(text.string == "one\ntwo")
    #expect(NoteAttributedText.document(from: text, original: orig).blocks == [.paragraph([TextRun("one")]), .paragraph([TextRun("two")])])
}

@Test @MainActor func codeBlockTogglesAndKeepsText() {
    let text = storage(NoteDocument(blocks: [.paragraph([TextRun("a = 1")])]))
    let orig = NoteDocument(blocks: [])
    NoteFormatting.apply(BlockFormat.codeBlock, to: text, range: NSRange(location: 0, length: 5))
    #expect(NoteAttributedText.document(from: text, original: orig).blocks == [.code("a = 1")])
    NoteFormatting.apply(BlockFormat.codeBlock, to: text, range: NSRange(location: 0, length: 5))
    #expect(NoteAttributedText.document(from: text, original: orig).blocks == [.paragraph([TextRun("a = 1")])])
}

@Test @MainActor func headingToBodyDropsTheForcedBold() {
    let text = storage(NoteDocument(blocks: [.heading(level: 1, [TextRun("Hi")])]))
    NoteFormatting.apply(BlockFormat.body, to: text, range: NSRange(location: 0, length: 2))
    #expect(NoteAttributedText.document(from: text, original: NoteDocument(blocks: [])).blocks == [.paragraph([TextRun("Hi")])])
}

@Test @MainActor func emojiAndCombiningCharactersSurviveInPlainAndBoldRuns() {
    for word in ["a😀b", "🇻🇳", "e\u{301}", "Tiếng Việt"] {
        let doc = NoteDocument(blocks: [.paragraph([TextRun(word, style: .bold), TextRun(" " + word)])])
        #expect(roundTrip(doc) == doc)
    }
}

@Test @MainActor func emojiNextToAnImageSurvives() {
    let doc = NoteDocument(blocks: [.image(attachmentIndex: 0), .paragraph([TextRun("😀")])])
    #expect(roundTrip(doc) == doc)
}

@Test @MainActor func textTypedAfterTheMarkKeepsItsCharacters() {
    let doc = NoteDocument(blocks: [.listItem(.bullet, indent: 0, [])])
    let text = NSMutableAttributedString(attributedString: NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail))
    text.append(NSAttributedString(string: "x", attributes: text.attributes(at: 0, effectiveRange: nil)))
    #expect(NoteAttributedText.document(from: text, original: doc).blocks == [.listItem(.bullet, indent: 0, [TextRun("x")])])
}

@Test @MainActor func textTypedAtColumnZeroIsKept() {
    let doc = NoteDocument(blocks: [.listItem(.bullet, indent: 0, [TextRun("one")])])
    let text = NSMutableAttributedString(attributedString: NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail))
    text.insert(NSAttributedString(string: "y", attributes: text.attributes(at: 0, effectiveRange: nil)), at: 0)
    let blocks = NoteAttributedText.document(from: text, original: doc).blocks
    #expect(blocks.count == 1)
    if case .listItem(_, _, let runs) = blocks[0] { #expect(runs.map(\.text).joined().contains("y")) } else { Issue.record("not a list item") }
}

@Test @MainActor func twoDigitNumberMarkIsStripped() {
    let items = (1...12).map { NoteBlock.listItem(.numbered, indent: 0, [TextRun("i\($0)")]) }
    let doc = NoteDocument(blocks: items)
    let text = NoteAttributedText.make(doc, images: [:], imageSize: .thumbnail)
    #expect(text.string.contains("12. i12"))
    #expect(NoteAttributedText.document(from: text, original: doc) == doc)
}

@Test func cleanTypingAttributesDropsTheMark() {
    let attributes = NoteAttributedText.cleanTypingAttributes([NoteAttribute.decoration: true, NoteAttribute.block: "bullet"])
    #expect(attributes[NoteAttribute.decoration] == nil)
    #expect(attributes[NoteAttribute.block] as? String == "bullet")
}

/// A list indent no note has (hostile data) is drawn at the deepest level, not trapped on.
@Test @MainActor func hugeIndentIsDrawnAtTheDeepestLevel() {
    let text = storage(NoteDocument(blocks: [.listItem(.bullet, indent: Int.max, [TextRun("a")])]))
    let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    #expect(style?.headIndent == NoteAttributedText.indentStep * CGFloat(NoteDocument.maxListIndent + 1))
}
