import AppKit
import NotchCore
import NotchShell
import NotesCore
import SwiftUI
import Testing
@testable import NotesFeature

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotesPageTests-\(UUID().uuidString)")
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
private struct PageHarness {
    let fake = FakeNotesService()
    let settings = NotesSettings(store: NotesSettingsStore(defaults: UserDefaults(suiteName: "notes.page.\(UUID().uuidString)")!))
    let folderID: String
    let store: NotesStore

    init() async throws {
        folderID = try await fake.createFolder(named: "Notes").id
        store = NotesStore(service: fake, database: nil, cache: NoteImageCache(root: temporaryDirectory()), settings: settings,
                           debounce: .seconds(30), staging: NoteImageStaging(folder: temporaryDirectory()))
    }

    func note(_ lines: [String], locked: Bool = false) -> String {
        fake.addNote(lines.first ?? "", in: folderID, html: lines.map { "<div>\($0)</div>" }.joined(),
                     plainText: lines.joined(separator: "\n"), locked: locked)
    }

    /// The page's editor as SwiftUI builds it, with its toolbar handle attached.
    func windowEditor() -> (NoteEditorHandle, NSView) {
        let handle = NoteEditorHandle()
        let host = NSHostingView(rootView: NoteEditorView(store: store, imageSize: .fitWidth(400)).handle(handle))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        host.layoutSubtreeIfNeeded()
        return (handle, host)
    }
}

@MainActor @Suite struct NotesPageTests {
    @Test func createFolderSelectsIt() async throws {
        let h = try await PageHarness()
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

    @Test func newNoteGoesToTheChosenFolder() async throws {
        let h = try await PageHarness()
        await h.store.refresh()
        let work = try #require(await h.store.createFolder(named: "Work"))
        await h.store.newNote(in: work.id)
        let id = try #require(h.store.open?.id)
        #expect(try await h.fake.notes(in: work.id).map(\.id) == [id])
        #expect(h.store.notes.map(\.id) == [id])
    }

    @Test func cancellingTheDeleteKeepsTheNote() async throws {
        let h = try await PageHarness()
        let id = h.note(["Keep me"])
        await h.store.refresh()
        let model = NotesPageModel()
        model.askToDelete(id)
        #expect(model.deletingID == id)
        model.cancelDelete()
        #expect(model.deletingID == nil)
        #expect(try await h.fake.notes(in: nil).map(\.id) == [id])
    }

    @Test func confirmingTheDeleteRemovesTheNote() async throws {
        let h = try await PageHarness()
        let id = h.note(["Delete me"])
        let other = h.note(["Stay"])
        await h.store.refresh()
        let model = NotesPageModel()
        model.askToDelete(id)
        await model.confirmDelete(in: h.store)
        #expect(model.deletingID == nil)
        #expect(h.store.notes.map(\.id) == [other])
    }

    @Test func deletingTheOpenNoteClosesIt() async throws {
        let h = try await PageHarness()
        let id = h.note(["Open and deleted"])
        await h.store.refresh()
        await h.store.openNote(id)
        #expect(h.store.open?.id == id)
        let model = NotesPageModel()
        model.askToDelete(id)
        await model.confirmDelete(in: h.store)
        #expect(h.store.open == nil)
    }

    @Test func firstToOpenPrefersTheLatestOpenedHere() {
        func summary(_ id: String, _ age: TimeInterval, locked: Bool = false) -> NoteSummary {
            NoteSummary(id: id, name: id, folderID: "f", modified: Date(timeIntervalSinceNow: -age), snippet: "",
                        hasImages: false, isLocked: locked)
        }
        let notes = [summary("a", 300), summary("b", 200), summary("c", 100)]
        #expect(NotesController.firstToOpen(notes, recent: ["b", "a"])?.id == "b")
        #expect(NotesController.firstToOpen(notes, recent: ["gone", "a"])?.id == "a")
        #expect(NotesController.firstToOpen(notes, recent: [])?.id == "c")
        let lockedB = [summary("a", 300), summary("b", 200, locked: true), summary("c", 100)]
        #expect(NotesController.firstToOpen(lockedB, recent: ["b", "a"])?.id == "a")
        #expect(NotesController.firstToOpen([summary("x", 1, locked: true)], recent: []) == nil)
    }

    @Test func choosingAFolderListsItsNotesAndClosesThePicker() async throws {
        let h = try await PageHarness()
        let work = try await h.fake.createFolder(named: "Work")
        let home = h.note(["At home"])
        let office = h.fake.addNote("At work", in: work.id, html: "<div>At work</div>", plainText: "At work")
        await h.store.refresh()
        #expect(Set(h.store.notes.map(\.id)) == [home, office])
        let model = NotesPageModel()
        model.isChoosingFolder = true
        model.deletingID = home
        await model.choose(folder: work.id, in: h.store)
        #expect(h.store.selectedFolderID == work.id)
        #expect(h.store.notes.map(\.id) == [office])
        #expect(!model.isChoosingFolder)
        #expect(model.deletingID == nil)
    }

    @Test func choosingAllNotesListsEveryNote() async throws {
        let h = try await PageHarness()
        let work = try await h.fake.createFolder(named: "Work")
        h.note(["At home"])
        h.fake.addNote("At work", in: work.id, html: "<div>At work</div>", plainText: "At work")
        h.store.selectedFolderID = work.id
        await h.store.refresh()
        #expect(h.store.notes.count == 1)
        let model = NotesPageModel()
        await model.choose(folder: nil, in: h.store)
        #expect(h.store.selectedFolderID == nil)
        #expect(h.store.notes.count == 2)
    }

    @Test func anEmptyFolderNameMakesNothing() async throws {
        let h = try await PageHarness()
        await h.store.refresh()
        let model = NotesPageModel()
        model.isAddingFolder = true
        model.newFolderName = "   "
        #expect(await model.createFolder(in: h.store) == false)
        #expect(model.isAddingFolder)
        #expect(h.store.folders.count == 1)
    }

    @Test func aNewFolderIsChosen() async throws {
        let h = try await PageHarness()
        await h.store.refresh()
        let model = NotesPageModel()
        model.isChoosingFolder = true
        model.isAddingFolder = true
        model.newFolderName = "Work"
        #expect(await model.createFolder(in: h.store))
        let made = try #require(h.store.folders.first { $0.name == "Work" })
        #expect(h.store.selectedFolderID == made.id)
        #expect(!model.isAddingFolder)
        #expect(!model.isChoosingFolder)
        #expect(model.newFolderName.isEmpty)
    }

    @Test func accountsKeepNotesOrder() {
        let a = NoteFolder(id: "a", name: "A", account: "iCloud", noteCount: 1)
        let b = NoteFolder(id: "b", name: "B", account: "On My Mac", noteCount: 2)
        let c = NoteFolder(id: "c", name: "C", account: "iCloud", noteCount: 3)
        let accounts = NoteFolderPicker.accounts(of: [a, b, c])
        #expect(accounts.map(\.name) == ["iCloud", "On My Mac"])
        #expect(accounts.map { $0.folders.map(\.id) } == [["a", "c"], ["b"]])
    }

    @Test func windowToolbarBoldAppliesToWindowEditor() async throws {
        let h = try await PageHarness()
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
        let h = try await PageHarness()
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
        #expect(NoteEditorCoordinator.isEditable(editable, .saved, isReloading: false))
        #expect(!NoteEditorCoordinator.isEditable(editable, .conflict, isReloading: false))
        #expect(!NoteEditorCoordinator.isEditable(editable, .deleted, isReloading: false))
        #expect(!NoteEditorCoordinator.isEditable(editable, .saved, isReloading: true))
        #expect(!NoteEditorCoordinator.isEditable(open, .saved, isReloading: false))
        #expect(!NoteEditorCoordinator.isEditable(nil, .saved, isReloading: false))
        _ = host
    }

    @Test func toolbarBlockFormatsAreUndoable() async throws {
        let h = try await PageHarness()
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
        let h = try await PageHarness()
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
        let h = try await PageHarness()
        await h.store.openNote(h.note(["One"]))
        let (_, notchHost) = h.windowEditor()
        let (windowHandle, windowHost) = h.windowEditor()
        let notchEditor = try #require(notchHost.subviewsEditor)
        let windowEditor = try #require(windowHandle.editor)
        let rebuilds = notchEditor.rebuildCount
        for word in [" two", " three", " four"] {
            windowEditor.textView.setSelectedRange(NSRange(location: windowEditor.textView.string.utf16.count, length: 0))
            windowEditor.textView.insertText(word, replacementRange: windowEditor.textView.selectedRange())
            windowEditor.commitNow()
        }
        // The other editor is in no key window: it shows the edits once the typing pauses, rebuilt once for all.
        #expect(notchEditor.textView.string == "One")
        try await waitUntil("the other editor caught up") { notchEditor.textView.string == "One two three four" }
        #expect(notchEditor.rebuildCount == rebuilds + 1)
        _ = windowHost
    }

    @Test func keystrokeOnOlderTextNeverReplacesTheOtherEditorsEdit() async throws {
        let h = try await PageHarness()
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
        let h = try await PageHarness()
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
}

private extension NSView {
    /// The editor coordinator behind the first text view found in this view.
    var subviewsEditor: NoteEditorCoordinator? {
        if let text = self as? NoteTextView { return text.host as? NoteEditorCoordinator }
        for subview in subviews { if let found = subview.subviewsEditor { return found } }
        return nil
    }
}


/// What the controller asked of the notch.
@MainActor
private final class PresenterLog {
    var shown = 0
    var focused = 0
    var keeps: [Bool] = []
    var hidden = false
    var notesOpened = 0

    var presenter: NotesPresenter {
        NotesPresenter(showPage: { self.shown += 1 }, focusEditor: { self.focused += 1 },
                       isPageHidden: { self.hidden }, setKeepsOpen: { self.keeps.append($0) },
                       openNotesApp: { self.notesOpened += 1 })
    }
}

@MainActor @Suite struct NotesPageControllerTests {
    private func controller(_ h: PageHarness) -> (NotesController, PresenterLog) {
        let notch = NotchController(settings: ShellSettings(store: ShellSettingsStore(
            defaults: UserDefaults(suiteName: "notes.shell.\(UUID().uuidString)")!)))
        let controller = NotesController(settings: h.settings, notch: notch, service: h.fake, database: nil,
                                         cache: NoteImageCache(root: temporaryDirectory()))
        let log = PresenterLog()
        controller.presenter = log.presenter
        return (controller, log)
    }

    @Test func newNoteShowsThePageBeforeTheNoteIsMade() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        h.fake.createDelay = .milliseconds(300)
        controller.newNote()
        #expect(log.shown == 1)
        #expect(controller.store.open == nil)
        try await waitUntil("the note was made and opened") { controller.store.open != nil }
        #expect(h.fake.calls("create") == 1)
        #expect(log.focused == 1)
        #expect(log.shown == 1)
    }

    @Test func newNoteThatCannotBeMadeStillShowsThePage() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        h.fake.accessValue = .denied
        controller.newNote()
        #expect(log.shown == 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.store.open == nil)
        #expect(log.focused == 0)
    }

    @Test func newNoteWithTheHiddenPageOpensItInNotes() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        log.hidden = true
        controller.newNote()
        try await waitUntil("the note was shown in Notes") { h.fake.calls("show") == 1 }
        #expect(log.shown == 0)
        #expect(h.fake.calls("create") == 1)
        #expect(log.notesOpened == 0)
    }

    @Test func newNoteWithTheHiddenPageAndNoNoteOpensNotes() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        log.hidden = true
        h.fake.accessValue = .denied
        controller.newNote()
        try await waitUntil("Notes was opened") { log.notesOpened == 1 }
        #expect(log.shown == 0)
        #expect(h.fake.calls("show") == 0)
    }

    @Test func showPageShowsThePage() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        controller.showPage()
        #expect(log.shown == 1)
    }

    @Test func timerRunsOnlyWhileThePageShowsWithoutFullDiskAccess() async throws {
        let h = try await PageHarness()
        let (controller, _) = controller(h)
        #expect(!controller.isRefreshingOnTimer)
        controller.pageShowingChanged(true)
        #expect(controller.isRefreshingOnTimer)
        controller.pageShowingChanged(false)
        #expect(!controller.isRefreshingOnTimer)
    }

    @Test func keepsTheNotchOpenWhileAnythingIsUnderWay() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        let model = controller.model
        let flags: [ReferenceWritableKeyPath<NotesPageModel, Bool>] = [
            \.isEditorFocused, \.isChoosingFolder, \.isAddingFolder, \.isChoosingImages,
        ]
        for flag in flags {
            model[keyPath: flag] = true
            #expect(log.keeps.last == true)
            model[keyPath: flag] = false
            #expect(log.keeps.last == false)
        }
        model.deletingID = "x"
        #expect(log.keeps.last == true)
        // Two reasons at once: letting go of one keeps the notch.
        model.isChoosingFolder = true
        model.deletingID = nil
        #expect(log.keeps.last == true)
        model.isChoosingFolder = false
        #expect(log.keeps.last == false)
        // Told only when the answer changes.
        #expect(zip(log.keeps, log.keeps.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test func leavingThePageClosesWhatWasOpenOnIt() async throws {
        let h = try await PageHarness()
        let (controller, log) = controller(h)
        controller.pageShowingChanged(true)
        controller.model.isChoosingFolder = true
        controller.model.isAddingFolder = true
        controller.model.newFolderName = "Wo"
        controller.model.deletingID = "x"
        controller.pageShowingChanged(false)
        #expect(!controller.model.isChoosingFolder)
        #expect(!controller.model.isAddingFolder)
        #expect(controller.model.newFolderName.isEmpty)
        #expect(controller.model.deletingID == nil)
        #expect(log.keeps.last == false)
    }
}
