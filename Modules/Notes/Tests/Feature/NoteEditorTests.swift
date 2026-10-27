import AppKit
import NotchCore
import NotchShell
import NotesCore
import Testing
@testable import NotesFeature

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NoteEditorTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A 1×1 PNG.
private let pngBytes: Data = {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}()

@MainActor
private struct EditorHarness {
    let fake = FakeNotesService()
    let settings = NotesSettings(store: NotesSettingsStore(defaults: UserDefaults(suiteName: "notes.editor.\(UUID().uuidString)")!))
    let folderID: String
    let store: NotesStore

    /// A long debounce, so an edit stays pending while the test looks at it.
    init() async throws {
        folderID = try await fake.createFolder(named: "Notes").id
        store = NotesStore(service: fake, database: nil, cache: NoteImageCache(root: temporaryDirectory()), settings: settings,
                           debounce: .seconds(30))
    }

    func note(_ lines: [String], locked: Bool = false) -> String {
        fake.addNote(lines.first ?? "", in: folderID, html: lines.map { "<div>\($0)</div>" }.joined(),
                     plainText: lines.joined(separator: "\n"), locked: locked)
    }

    func editor() -> NoteEditorCoordinator {
        NoteEditorView(store: store, imageSize: .thumbnail).makeCoordinator()
    }
}

private func key(_ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)!
}

/// Suites that run on the main actor one after another: the store tests time saves in tens of milliseconds,
/// and building text views beside them would hold the main actor long enough to upset those timings.
@Suite(.serialized) enum NotesMainActorSuites {}

extension NotesMainActorSuites {
@MainActor @Suite struct NoteEditorTests {
    @Test func commandBTogglesBoldInEditor() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Title", "body"]))
        let editor = h.editor()
        let text = editor.textView
        #expect(text.string == "Title\nbody")
        text.setSelectedRange(NSRange(location: 6, length: 4))
        #expect(text.performKeyEquivalent(with: key("b", .command)))
        let font = text.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        editor.commitNow()
        #expect(h.store.saveState == .pending)
        guard case .paragraph(let runs)? = h.store.open?.document.blocks.last else { Issue.record("no paragraph"); return }
        #expect(runs.first?.style.contains(.bold) == true)
    }

    @Test func readOnlyEditorIsNotEditable() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Secret"], locked: true))
        #expect(h.store.open?.safety != .editable)
        let editor = h.editor()
        #expect(!editor.textView.isEditable)
        #expect(!editor.textView.performKeyEquivalent(with: key("b", .command)))
    }

    @Test func pageHasNotesID() async throws {
        let h = try await EditorHarness()
        let notch = NotchController(settings: ShellSettings(store: ShellSettingsStore(
            defaults: UserDefaults(suiteName: "notes.shell.\(UUID().uuidString)")!)))
        let controller = NotesController(settings: h.settings, notch: notch, service: h.fake, database: nil,
                                          cache: NoteImageCache(root: temporaryDirectory()))
        #expect(controller.makePage().id == "notes")
    }

    @Test func editsCarryTheOpenGeneration() async throws {
        let h = try await EditorHarness()
        let first = h.note(["One"])
        let second = h.note(["Two"])
        await h.store.openNote(first)
        let editor = h.editor()
        let firstGeneration = try #require(h.store.open?.generation)
        // Typed into the first note; the switch happens before the edit is sent.
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editor.textView.insertText("!", replacementRange: editor.textView.selectedRange())
        await h.store.openNote(second)
        editor.commitNow()
        #expect(h.store.open?.id == second)
        #expect(h.store.open?.generation != firstGeneration)
        #expect(h.store.open?.document.plainText == "Two")
        #expect(editor.textView.string == "Two")
        // An edit now goes to the second note's load.
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editor.textView.insertText("?", replacementRange: editor.textView.selectedRange())
        editor.commitNow()
        #expect(h.store.open?.document.plainText == "Two?")
        #expect(h.store.saveState == .pending)
    }

    @Test func pastedImageGetsAnIndex() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Pic"]))
        let editor = h.editor()
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        let board = NSPasteboard(name: NSPasteboard.Name("notes.test.\(UUID().uuidString)"))
        board.clearContents()
        board.setData(pngBytes, forType: .png)
        #expect(editor.textView.insert(from: board))
        editor.commitNow()
        let blocks = h.store.open?.document.blocks ?? []
        let indexes = blocks.compactMap { block -> Int? in
            if case .image(let index) = block { return index }
            return nil
        }
        #expect(indexes.count == 1)
        if let index = indexes.first { #expect(h.store.open?.images[index] != nil) }
        // Every attachment character carries an index.
        let storage = try #require(editor.textView.textStorage)
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            #expect(storage.attribute(NoteAttribute.attachmentIndex, at: range.location, effectiveRange: nil) != nil)
        }
        board.releaseGlobally()
    }

    @Test func bareAttachmentsAreStripped() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Text"]))
        let editor = h.editor()
        let text = editor.textView
        text.setSelectedRange(NSRange(location: 4, length: 0))
        text.insertText(NSAttributedString(attachment: NSTextAttachment()), replacementRange: text.selectedRange())
        editor.commitNow()
        #expect(!text.string.contains("\u{FFFC}"))
        #expect(h.store.open?.document.plainText == "Text")
    }

    @Test func caretMovesOutOfBulletPrefix() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Title"]))
        let editor = h.editor()
        let text = editor.textView
        let storage = try #require(text.textStorage)
        // A bullet line after the title, as the editor builds it.
        let bullet = NoteAttributedText.make(NoteDocument(blocks: [.paragraph([TextRun("Title")]),
                                                                   .listItem(.bullet, indent: 0, [TextRun("item")])]),
                                             images: [:], imageSize: .thumbnail)
        storage.setAttributedString(bullet)
        // "Title\n• item": the prefix is at 6 and 7.
        let moved = editor.textView(text, willChangeSelectionFromCharacterRange: NSRange(location: 0, length: 0),
                                    toCharacterRange: NSRange(location: 6, length: 0))
        #expect(moved == NSRange(location: 8, length: 0))
        let inside = editor.textView(text, willChangeSelectionFromCharacterRange: NSRange(location: 10, length: 0),
                                     toCharacterRange: NSRange(location: 7, length: 0))
        #expect(inside == NSRange(location: 8, length: 0))
        // Moving left from just after the prefix goes to the line before.
        let left = editor.textView(text, willChangeSelectionFromCharacterRange: NSRange(location: 8, length: 0),
                                   toCharacterRange: NSRange(location: 7, length: 0))
        #expect(left == NSRange(location: 5, length: 0))
        let elsewhere = editor.textView(text, willChangeSelectionFromCharacterRange: NSRange(location: 0, length: 0),
                                        toCharacterRange: NSRange(location: 2, length: 0))
        #expect(elsewhere == NSRange(location: 2, length: 0))
    }

    @Test func typingAttributesNeverCarryDecoration() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Title"]))
        let editor = h.editor()
        let text = editor.textView
        let storage = try #require(text.textStorage)
        storage.setAttributedString(NoteAttributedText.make(
            NoteDocument(blocks: [.listItem(.bullet, indent: 0, [])]), images: [:], imageSize: .thumbnail))
        text.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(text.typingAttributes[NoteAttribute.decoration] == nil)
        text.insertText("x", replacementRange: text.selectedRange())
        #expect(text.typingAttributes[NoteAttribute.decoration] == nil)
        #expect(storage.attribute(NoteAttribute.decoration, at: 2, effectiveRange: nil) == nil)
        editor.commitNow()
        #expect(h.store.open?.document.blocks == [.listItem(.bullet, indent: 0, [TextRun("x")])])
    }

    @Test func returnInABulletContinuesTheList() async throws {
        let h = try await EditorHarness()
        await h.store.openNote(h.note(["Title"]))
        let editor = h.editor()
        let text = editor.textView
        text.textStorage?.setAttributedString(NoteAttributedText.make(
            NoteDocument(blocks: [.listItem(.bullet, indent: 0, [TextRun("a")])]), images: [:], imageSize: .thumbnail))
        text.setSelectedRange(NSRange(location: 3, length: 0))
        text.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        text.insertText("b", replacementRange: text.selectedRange())
        #expect(text.string == "• a\n• b")
        // Return on an empty item ends the list.
        text.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        text.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        editor.commitNow()
        #expect(h.store.open?.document.blocks == [.listItem(.bullet, indent: 0, [TextRun("a")]),
                                                  .listItem(.bullet, indent: 0, [TextRun("b")]), .paragraph([])])
    }
}
}
