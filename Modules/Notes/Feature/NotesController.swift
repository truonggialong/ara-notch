import AppKit
import Combine
import NotchCore
import NotchShell
import NotesCore
import SwiftUI

/// What the controller does on screen: the notch page shown, the caret put in the editor, and the notch kept open
/// while something on the page is under way. Tests replace it.
struct NotesPresenter {
    var showPage: @MainActor () -> Void
    var focusEditor: @MainActor () -> Void
    var isPageHidden: @MainActor () -> Bool
    var setKeepsOpen: @MainActor (Bool) -> Void
    var openNotesApp: @MainActor () -> Void
}

/// The Notes feature as the app sees it: the notch page, its settings, a new note, and saving whenever the
/// page is left. Talks to Notes through AppleScript (`NotesBridge`) and, with Full Disk Access, its database.
@MainActor
public final class NotesController {
    private static let pageID = "notes"
    /// The page asks for a taller sheet than the usual one, for the list and the editor.
    static let sheetHeight: CGFloat = 420
    /// Without Full Disk Access nothing tells AraNotch of changes made in Notes: the page lists again this often.
    static let refreshInterval: TimeInterval = 30

    let store: NotesStore
    private let settings: NotesSettings
    private let notch: NotchController
    let model = NotesPageModel()
    private let watchURL: URL?
    private var watcher: NoteStoreWatcher?
    private var cancellables: Set<AnyCancellable> = []
    private var isPageShowing = false
    /// True while a new note is being made: the page showing for it does not open another note meanwhile, which
    /// would queue a whole read in Notes before the note is made.
    private var isMakingNote = false
    private var refreshTimer: Timer?
    var presenter: NotesPresenter

    public convenience init(settings: NotesSettings, notch: NotchController) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "AraNotch", isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
        self.init(settings: settings, notch: notch, service: NotesBridge(), database: NoteStoreReader(),
                  cache: NoteImageCache(root: caches), watchURL: NoteStoreReader.defaultURL)
    }

    init(settings: NotesSettings, notch: NotchController, service: NotesService, database: NoteDatabase?,
         cache: NoteImageCache, watchURL: URL? = nil) {
        self.settings = settings
        self.notch = notch
        self.watchURL = watchURL
        store = NotesStore(service: service, database: database, cache: cache, settings: settings)
        presenter = NotesPresenter(
            showPage: { [weak notch] in
                notch?.selectPage(id: Self.pageID)
                notch?.open()
            },
            focusEditor: { [model] in model.editor.focus() },
            isPageHidden: { [weak notch] in notch?.isPageHidden(id: Self.pageID) ?? false },
            setKeepsOpen: { [weak notch] in notch?.setKeepsOpen($0, forPage: Self.pageID) },
            openNotesApp: {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            })
        model.onAppear = { [weak self] in self?.pageAppeared() }
        model.onNewNote = { [weak self] in self?.newNoteHere() }
        model.onEditorFocus = { [weak self] isFocused in self?.model.isEditorFocused = isFocused }
        // Whatever is under way on the page (typing, a folder being chosen, a delete being asked) keeps the notch.
        model.$keepsNotchOpen
            .removeDuplicates()
            .sink { [weak self] keeps in self?.presenter.setKeepsOpen(keeps) }
            .store(in: &cancellables)
        // An editor taken away (its note closed or deleted) is never told it lost the keyboard: let the notch go.
        store.$open
            .filter { $0 == nil }
            .sink { [model] _ in model.isEditorFocused = false }
            .store(in: &cancellables)
    }

    // MARK: Pages and settings

    public func makePage() -> NotchPage {
        var page = NotchPage(id: Self.pageID, titleKey: "notes.page.title", symbolName: "note.text") { [store, model] in
            NotesPageView(store: store, model: model)
        }
        page.keyHandler = { [model] key, _ in model.handleKey(key) }
        return page
    }

    /// The shortcut for a new note, for Settings › Tools.
    public func makeToolSettings() -> AnyView {
        AnyView(ShortcutRow(center: notch.shortcuts, action: .newNote, titleKey: "shortcut.newNote",
                            noteKey: "settings.notes.newNote.note"))
    }

    /// The default folder and the two permissions, for Settings › Notch pages.
    public func makePageSettings() -> AnyView {
        AnyView(NotesPageSettings(store: store, settings: settings))
    }

    // MARK: Actions

    /// Makes an empty note in the default folder and opens it on the notch's Notes page, the caret in it at once,
    /// before Notes made the note (it opens as a draft); when none could be made (no access yet, no folder) the page
    /// shows the access card, so the command never does nothing. With the page hidden the note opens in Notes instead.
    public func newNote() {
        let isHidden = presenter.isPageHidden()
        isMakingNote = true
        if !isHidden { presenter.showPage() }
        Task {
            await flush()
            let before = store.open?.generation
            await store.newNote(opened: isHidden ? nil : { self.presenter.focusEditor() })
            isMakingNote = false
            guard isHidden else { return }
            let made = store.open.flatMap { $0.generation != before && !NotesStore.isDraft($0.id) ? $0.id : nil }
            if let made { await store.showInNotes(made) } else { presenter.openNotesApp() }
        }
    }

    /// Opens the notch on the Notes page.
    public func showPage() {
        presenter.showPage()
    }

    /// "+" on the page: a note in the folder shown there (all notes: the default folder).
    private func newNoteHere() {
        Task {
            await flush()
            await store.newNote(in: store.selectedFolderID, opened: { self.presenter.focusEditor() })
        }
    }

    /// Writes the raw (compressed) body of a note's database row to `file`; for automated checks. False when
    /// the note has no row key or the database cannot be read (no Full Disk Access).
    public func dumpNoteData(noteID: String, to file: URL) -> Bool {
        let reader = NoteStoreReader()
        guard let key = NotesIDs.databaseKey(of: noteID, entity: "ICNote"),
              let data = reader.rawData(forNoteKey: key) else { return false }
        // Beside it, each attachment: identifier, type in the protobuf, type of its row, media file.
        let attachments = (try? NoteStoreDecoder.decode(data))?.attachments ?? []
        let types = reader.attachmentTypes(forIdentifiers: attachments.map(\.identifier))
        let lines = zip(attachments, types).map { attachment, type in
            "\(attachment.identifier) \(attachment.uti) \(type ?? "-") \(reader.attachmentFile(forIdentifier: attachment.identifier)?.lastPathComponent ?? "-")"
        }
        try? lines.joined(separator: "\n").write(to: file.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        return (try? data.write(to: file)) != nil
    }

    /// For checks by hand: opens the note, adds a paragraph at its end the way the editor would, saves, and writes
    /// how that went (the note's safety, the save state) to `report`.
    public func appendParagraph(_ text: String, toNote noteID: String, report: URL) async {
        await store.openNote(noteID)
        var lines: [String] = []
        if let open = store.open, open.id == noteID {
            lines.append("safety: \(open.safety)")
            if open.safety == .editable {
                var document = open.document
                document.blocks.append(.paragraph([TextRun(text)]))
                store.edit(document, generation: open.generation)
                await store.flush()
            }
        } else {
            lines.append("not opened")
        }
        lines.append("save: \(store.saveState)")
        try? lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
    }

    public func start() {
        notch.shortcuts.setHandler(.newNote) { [weak self] in self?.newNote() }
        notch.setSheetHeight(Self.sheetHeight, forPage: Self.pageID)
        // Leaving the page, closing the notch or leaving the app saves what was typed.
        Publishers.CombineLatest(notch.isOpenPublisher, notch.selectedPagePublisher)
            .map { isOpen, page in isOpen && page == Self.pageID }
            .removeDuplicates()
            .sink { [weak self] isShowing in self?.pageShowingChanged(isShowing) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in Task { await self?.flush() } }
            .store(in: &cancellables)
        // With Full Disk Access, Notes' own writes show while the page is up.
        store.$fullView
            .removeDuplicates()
            .sink { [weak self] fullView in
                self?.watch(fullView)
                self?.updateRefreshTimer(fullView: fullView)
            }
            .store(in: &cancellables)
    }

    /// For quitting: writes what was typed and not saved yet, waiting at most `limit` so a Notes that does not
    /// answer cannot hold quitting up. False when the limit was reached first.
    @discardableResult
    public func saveBeforeQuitting(limit: Duration = .seconds(5)) async -> Bool {
        // Whichever comes first: the save done, or the limit.
        let (outcomes, continuation) = AsyncStream<Bool>.makeStream()
        Task {
            await flush()
            continuation.yield(true)
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            continuation.yield(false)
        }
        var first = outcomes.makeAsyncIterator()
        let finished = await first.next() ?? false
        timer.cancel()
        continuation.finish()
        return finished
    }

    /// Hands the editor's last keystrokes to the store and waits until they are written.
    func flush() async {
        NoteEditorCoordinator.commitAll()
        await store.flush()
    }

    // MARK: Refreshing

    /// The page is on screen (notch open, Notes selected) or stopped being so. Only this starts a closed Notes:
    /// the notch builds the selected page's view even while it is closed, so `onAppear` is no sign of being seen.
    func pageShowingChanged(_ isShowing: Bool) {
        guard isShowing != isPageShowing else { return }
        isPageShowing = isShowing
        updateRefreshTimer(fullView: store.fullView)
        if isShowing {
            load(launching: true)
        } else {
            model.closeWhatIsOpen()
            Task { await flush() }
        }
    }

    /// The page's view appeared: lists again, starting Notes only when the page is really showing.
    func pageAppeared() {
        load(launching: isPageShowing)
    }

    /// Lists again, then opens `noteID`, or (none given and nothing open) the latest note opened here or else the
    /// newest one, when it can be opened.
    private func load(launching: Bool, noteID: String? = nil) {
        Task {
            await refreshAfterChange(launchingNotes: launching)
            model.hasChecked = true
            guard store.access == .granted else { return }
            if let noteID {
                guard store.open?.id != noteID else { return }
                NoteEditorCoordinator.commitAll()
                await store.openNote(noteID)
            } else if store.open == nil, !isMakingNote, let first = Self.firstToOpen(store.notes, recent: settings.recentIDs) {
                await store.openNote(first.id)
            }
        }
    }

    /// The note opened when the page shows with none open: the latest one opened here that is still listed and not
    /// locked, or else the newest one not locked.
    static func firstToOpen(_ notes: [NoteSummary], recent: [String]) -> NoteSummary? {
        let open = notes.filter { !$0.isLocked }
        return recent.lazy.compactMap { id in open.first { $0.id == id } }.first
            ?? open.max { $0.modified < $1.modified }
    }

    /// Refreshes every 30 seconds while the page is showing and no database change can be watched.
    private func updateRefreshTimer(fullView: Bool) {
        guard isPageShowing, !fullView else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshAfterChange(launchingNotes: false) }
            }
        }
    }

    var isRefreshingOnTimer: Bool { refreshTimer != nil }

    private func watch(_ fullView: Bool) {
        guard fullView, watcher == nil, let watchURL else {
            if !fullView {
                watcher?.stop()
                watcher = nil
            }
            return
        }
        watcher = NoteStoreWatcher(url: watchURL) { [weak self] in
            guard let self, self.isPageShowing else { return }
            Task { await self.refreshAfterChange(launchingNotes: false) }
        }
    }

    /// Lists the notes again, and reads the open note again when it changed in Notes and nothing typed here
    /// waits to be saved (AraNotch's own writes move `openedAt` along, so they do not count).
    /// `launchingNotes`: start a closed Notes (the page appears), not for a database change.
    private func refreshAfterChange(launchingNotes: Bool) async {
        await store.refresh(launchingNotes: launchingNotes)
        // Keystrokes not sent yet make the note pending, so they are never read over.
        NoteEditorCoordinator.commitAll()
        guard let open = store.open, store.saveState == .saved,
              let summary = store.notes.first(where: { $0.id == open.id }),
              summary.modified > open.openedAt else { return }
        await store.reloadOpenNote()
    }
}

/// Settings › Notch pages › Notes: where new notes go, and the two permissions.
struct NotesPageSettings: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: NotesSettings

    var body: some View {
        Picker(selection: Binding(get: { settings.defaultFolderID ?? "" },
                                  set: { settings.defaultFolderID = $0.isEmpty ? nil : $0 })) {
            Text(L10n.string("settings.notes.defaultFolder.first")).tag("")
            ForEach(store.folders) { folder in
                Text("\(folder.name) (\(folder.account))").tag(folder.id)
            }
        } label: {
            Text(L10n.string("settings.notes.defaultFolder"))
            AraSettingsNote(L10n.string("settings.notes.defaultFolder.note"))
        }
        .disabled(store.access != .granted)
        .onAppear {
            // Reads only what is allowed already; never asks.
            Task { await store.refresh() }
        }
        permissionRow(titleKey: "settings.notes.automation", isGranted: store.access == .granted,
                      noteKey: store.access == .granted ? "settings.notes.automation.granted" : "settings.notes.automation.note") {
            if store.access == .denied {
                NotesPrivacyPane.open(NotesPrivacyPane.automation)
            } else {
                Task { await store.requestAccess() }
            }
        }
        permissionRow(titleKey: "settings.notes.fullDisk", isGranted: store.fullView,
                      noteKey: store.fullView ? "settings.notes.fullDisk.granted" : "settings.notes.fullDisk.note") {
            NotesPrivacyPane.open(NotesPrivacyPane.fullDiskAccess)
        }
    }

    private func permissionRow(titleKey: String, isGranted: Bool, noteKey: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string(titleKey))
                AraSettingsNote(L10n.string(noteKey))
            }
            Spacer(minLength: 8)
            if !isGranted {
                Button(L10n.string("settings.notes.permission.open"), action: action)
            }
        }
    }
}
