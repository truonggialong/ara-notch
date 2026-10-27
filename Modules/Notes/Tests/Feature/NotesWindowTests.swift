import AppKit
import NotchCore
import NotchShell
import NotesCore
import SwiftUI
import Testing
@testable import NotesFeature

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotesWindowTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A 2×2 PNG.
private let pngBytes: Data = {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}()

@MainActor
private struct WindowHarness {
    let fake = FakeNotesService()
    let settings = NotesSettings(store: NotesSettingsStore(defaults: UserDefaults(suiteName: "notes.window.\(UUID().uuidString)")!))
    let folderID: String
    let store: NotesStore

    init() async throws {
        folderID = try await fake.createFolder(named: "Notes").id
        store = NotesStore(service: fake, database: nil, cache: NoteImageCache(root: temporaryDirectory()), settings: settings,
                           debounce: .seconds(30))
    }

    func note(_ lines: [String], locked: Bool = false) -> String {
        fake.addNote(lines.first ?? "", in: folderID, html: lines.map { "<div>\($0)</div>" }.joined(),
                     plainText: lines.joined(separator: "\n"), locked: locked)
    }

    /// The window's editor as SwiftUI builds it, with its toolbar handle attached.
    func windowEditor() -> (NoteEditorHandle, NSView) {
        let handle = NoteEditorHandle()
        let host = NSHostingView(rootView: NoteEditorView(store: store, imageSize: .fitWidth(400)).handle(handle))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        host.layoutSubtreeIfNeeded()
        return (handle, host)
    }
}

@MainActor @Suite struct NotesWindowTests {
    @Test func createFolderSelectsIt() async throws {
        let h = try await WindowHarness()
        h.note(["In Notes"])
        await h.store.refresh()
        #expect(h.store.notes.count == 1)
        let folder = await h.store.createFolder(named: "  Work  ")
        #expect(folder?.name == "Work")
        #expect(h.store.selectedFolderID == folder?.id)
        #expect(h.store.folders.contains { $0.id == folder?.id })
        #expect(h.store.notes.isEmpty)
        // An empty name makes nothing.
        #expect(await h.store.createFolder(named: "   ") == nil)
        #expect(h.store.folders.count == 2)
    }

    @Test func newNoteFromTheWindowGoesToTheChosenFolder() async throws {
        let h = try await WindowHarness()
        await h.store.refresh()
        let work = try #require(await h.store.createFolder(named: "Work"))
        await h.store.newNote(in: work.id)
        let id = try #require(h.store.open?.id)
        #expect(try await h.fake.notes(in: work.id).map(\.id) == [id])
        #expect(h.store.notes.map(\.id) == [id])
    }

    @Test func windowToolbarBoldAppliesToWindowEditor() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["Title", "body"]))
        let generation = try #require(h.store.open?.generation)
        let (handle, host) = h.windowEditor()
        let editor = try #require(handle.editor)
        #expect(handle.isEditable)
        editor.textView.setSelectedRange(NSRange(location: 6, length: 4))
        #expect(handle.apply(.bold))
        let font = editor.textView.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(handle.active.contains(.bold))
        editor.commitNow()
        #expect(h.store.saveState == .pending)
        #expect(h.store.open?.generation == generation)
        guard case .paragraph(let runs)? = h.store.open?.document.blocks.last else { Issue.record("no paragraph"); return }
        #expect(runs.first?.style.contains(.bold) == true)
        _ = host
    }

    @Test func toolbarDisabledWhenReadOnly() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["Secret"], locked: true))
        let (handle, host) = h.windowEditor()
        #expect(!handle.isEditable)
        handle.editor?.textView.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(!handle.apply(.bold))
        #expect(!handle.apply(.heading))
        #expect(h.store.saveState == .saved)
        let open = try #require(h.store.open)
        var editable = open
        editable.safety = .editable
        #expect(NoteEditorCoordinator.isEditable(editable, .saved))
        #expect(!NoteEditorCoordinator.isEditable(editable, .conflict))
        #expect(!NoteEditorCoordinator.isEditable(editable, .deleted))
        #expect(!NoteEditorCoordinator.isEditable(open, .saved))
        #expect(!NoteEditorCoordinator.isEditable(nil, .saved))
        _ = host
    }

    @Test func toolbarBlockFormatsAreUndoable() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["Title", "body"]))
        let (handle, host) = h.windowEditor()
        // In a window (never shown), so the text has an undo manager; one undo group per toolbar click.
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let editor = try #require(handle.editor)
        window.makeFirstResponder(editor.textView)
        let undo = try #require(editor.textView.undoManager)
        undo.groupsByEvent = false
        editor.textView.setSelectedRange(NSRange(location: 7, length: 0))
        undo.beginUndoGrouping()
        #expect(handle.apply(.bulletList))
        undo.endUndoGrouping()
        #expect(editor.textView.string == "Title\n• body")
        #expect(editor.textView.selectedRange().location == 9)
        undo.beginUndoGrouping()
        #expect(handle.apply(.heading))
        undo.endUndoGrouping()
        #expect(editor.textView.string == "Title\nbody")
        editor.commitNow()
        guard case .heading(let level, _)? = h.store.open?.document.blocks.last else { Issue.record("no heading"); return }
        #expect(level == 2)
        // Undo does not tell the delegate the text changed; the edit is still sent.
        undo.undo()
        #expect(editor.textView.string == "Title\n• body")
        editor.commitNow()
        guard case .listItem(.bullet, _, _)? = h.store.open?.document.blocks.last else { Issue.record("no bullet"); return }
    }

    @Test func insertImageGoesThroughThePastePath() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["Title"]))
        let (handle, host) = h.windowEditor()
        let editor = try #require(handle.editor)
        let file = temporaryDirectory().appendingPathComponent("picture.png")
        try pngBytes.write(to: file)
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(handle.insertImage(from: file))
        let storage = try #require(editor.textView.textStorage)
        let marker = (storage.string as NSString).range(of: "\u{FFFC}")
        #expect(marker.location != NSNotFound)
        let index = storage.attribute(NoteAttribute.attachmentIndex, at: marker.location, effectiveRange: nil) as? Int
        #expect(index != nil)
        #expect(index.flatMap { h.store.open?.images[$0] } != nil)
        editor.commitNow()
        #expect(h.store.open?.document.blocks.contains { if case .image = $0 { return true } else { return false } } == true)
        _ = host
    }

    @Test func secondEditorFollowsEditsOfTheFirst() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["One"]))
        let (_, notchHost) = h.windowEditor()
        let (windowHandle, windowHost) = h.windowEditor()
        let notchEditor = try #require(notchHost.subviewsEditor)
        let windowEditor = try #require(windowHandle.editor)
        windowEditor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        windowEditor.textView.insertText(" two", replacementRange: windowEditor.textView.selectedRange())
        windowEditor.commitNow()
        // The other editor is in no key window: it shows the edit at once.
        #expect(notchEditor.textView.string == "One two")
        _ = windowHost
    }

    @Test func keystrokeOnOlderTextNeverReplacesTheOtherEditorsEdit() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["One"]))
        let (_, notchHost) = h.windowEditor()
        let (windowHandle, windowHost) = h.windowEditor()
        let notchEditor = try #require(notchHost.subviewsEditor)
        let windowEditor = try #require(windowHandle.editor)
        // The notch's text has the keyboard in its own window: it catches up only a moment later.
        notchEditor.windowIsKey = { true }
        windowEditor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        windowEditor.textView.insertText(" two", replacementRange: windowEditor.textView.selectedRange())
        windowEditor.commitNow()
        #expect(notchEditor.textView.string == "One")
        // A keystroke there before it caught up.
        notchEditor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        notchEditor.textView.insertText("X", replacementRange: notchEditor.textView.selectedRange())
        notchEditor.commitNow()
        #expect(h.store.open?.document.plainText == "One two")
        #expect(notchEditor.textView.string == "One two")
        #expect(h.store.caughtUp)
        // The window's next keystroke is sent as usual.
        windowEditor.textView.setSelectedRange(NSRange(location: 7, length: 0))
        windowEditor.textView.insertText("!", replacementRange: windowEditor.textView.selectedRange())
        windowEditor.commitNow()
        #expect(h.store.open?.document.plainText == "One two!")
        try await waitUntil("the note about it went away", timeout: .seconds(4)) { !h.store.caughtUp }
        _ = windowHost
    }

    @Test func undoNeverSendsABareAttachment() async throws {
        let h = try await WindowHarness()
        await h.store.openNote(h.note(["Title"]))
        let (handle, host) = h.windowEditor()
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let editor = try #require(handle.editor)
        let text = editor.textView
        let storage = try #require(text.textStorage)
        let undo = try #require(text.undoManager)
        undo.groupsByEvent = false
        // A bare attachment put in without the delegate hearing of it (as if it slipped past), then deleted normally.
        let bare = NSAttributedString(attachment: NSTextAttachment())
        undo.beginUndoGrouping()
        #expect(text.shouldChangeText(in: NSRange(location: 5, length: 0), replacementString: bare.string))
        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: bare)
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        #expect(text.shouldChangeText(in: NSRange(location: 5, length: 1), replacementString: ""))
        storage.replaceCharacters(in: NSRange(location: 5, length: 1), with: "")
        text.didChangeText()
        undo.endUndoGrouping()
        editor.commitNow()
        // ⌘Z brings the bare attachment back; what is sent never has it.
        undo.undo()
        undo.beginUndoGrouping()   // the strip is an undoable change of its own
        editor.commitNow()
        undo.endUndoGrouping()
        #expect(!(text.string.contains("\u{FFFC}")))
        #expect(h.store.open?.document.plainText.contains("\u{FFFC}") == false)
        #expect(h.store.open?.document.plainText == "Title")
    }

    @Test func windowBuildsOffscreen() async throws {
        let h = try await WindowHarness()
        h.note(["Hello"])
        await h.store.refresh()
        let controller = NotesWindowController(store: h.store, page: NotesPageModel())
        let window = controller.window
        #expect(window.title == L10n.string("notes.window.title"))
        #expect(window.frameAutosaveName == "AraNotesWindow")
        #expect(!window.isReleasedWhenClosed)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.contentView != nil)
        #expect(!window.isVisible)
    }

    @Test func openingTheWindowStartsNotes() async throws {
        let h = try await WindowHarness()
        h.fake.accessValue = .notRunning
        h.fake.accessAfterLaunch = .granted
        let notch = NotchController(settings: ShellSettings(store: ShellSettingsStore(
            defaults: UserDefaults(suiteName: "notes.shell.\(UUID().uuidString)")!)))
        let controller = NotesController(settings: h.settings, notch: notch, service: h.fake, database: nil,
                                          cache: NoteImageCache(root: temporaryDirectory()))
        controller.windowShowingChanged(true)
        try await waitUntil("Notes was started") { h.fake.launchCalls == 1 }
        try await waitUntil("access is known") { controller.store.access == .granted }
        // No Full Disk Access (no database): the open window lists again on a timer, stopped when it closes.
        #expect(controller.isRefreshingOnTimer)
        // In the Dock it pauses, and comes back with the window.
        controller.windowMiniaturizedChanged(true)
        #expect(!controller.isRefreshingOnTimer)
        controller.windowMiniaturizedChanged(false)
        #expect(controller.isRefreshingOnTimer)
        controller.windowShowingChanged(false)
        #expect(!controller.isRefreshingOnTimer)
    }
}

private extension NSView {
    /// The editor coordinator behind the first text view found in this view.
    var subviewsEditor: NoteEditorCoordinator? {
        if let text = self as? NoteTextView { return text.host as? NoteEditorCoordinator }
        for subview in subviews { if let found = subview.subviewsEditor { return found } }
        return nil
    }
}

