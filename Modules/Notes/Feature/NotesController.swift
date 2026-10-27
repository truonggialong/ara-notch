import AppKit
import Combine
import NotchCore
import NotchShell
import SwiftUI

/// The Notes feature as the app sees it: the notch page, its settings, a new note, and saving whenever the
/// page is left. Talks to Notes through AppleScript (`NotesBridge`) and, with Full Disk Access, its database.
@MainActor
public final class NotesController {
    private static let pageID = "notes"
    /// The page asks for a taller sheet than the usual one, for the editor.
    private static let sheetHeight: CGFloat = 300
    /// Without Full Disk Access nothing tells AraNotch of changes made in Notes: the open window lists again this often.
    static let windowRefreshInterval: TimeInterval = 30

    let store: NotesStore
    private let settings: NotesSettings
    private let notch: NotchController
    let model = NotesPageModel()
    private let watchURL: URL?
    private var watcher: NoteStoreWatcher?
    private var cancellables: Set<AnyCancellable> = []
    private var isPageShowing = false
    private var window: NotesWindowController?
    private(set) var isWindowShowing = false
    private var isWindowMiniaturized = false
    private var refreshTimer: Timer?

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
        model.onAppear = { [weak self] in self?.pageAppeared() }
        model.onShowWindow = { [weak self] id in self?.showWindow(noteID: id) }
        model.onNewNote = { [weak self] in self?.newNote() }
        model.onEditorFocus = { [weak self] isFocused in
            self?.notch.setKeepsOpen(isFocused, forPage: Self.pageID)
        }
    }

    // MARK: Pages and settings

    public func makePage() -> NotchPage {
        NotchPage(id: Self.pageID, titleKey: "notes.page.title", symbolName: "note.text") { [store, settings, model] in
            NotesPageView(store: store, settings: settings, model: model)
        }
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

    /// Makes an empty note in the default folder and opens it in the window. When no note could be made (no access
    /// yet, no folder) the window opens all the same: it shows the access card, so the command never does nothing.
    public func newNote() {
        Task {
            await flush()
            let before = store.open?.generation
            await store.newNote()
            let made = store.open.flatMap { $0.generation != before ? $0.id : nil }
            showWindow(noteID: made)
        }
    }

    /// Opens the Notes window, on a note when one is given (nil: the open note, or else the latest one).
    public func showWindow(noteID: String? = nil) {
        let controller = window ?? makeWindow()
        controller.setHiddenFromCapture(notch.settings.hidesFromCapture)
        controller.show()
        windowShowingChanged(true, noteID: noteID)
    }

    private func makeWindow() -> NotesWindowController {
        let controller = NotesWindowController(store: store, page: model)
        controller.onClose = { [weak self] in self?.windowShowingChanged(false) }
        controller.onMiniaturize = { [weak self] in self?.windowMiniaturizedChanged($0) }
        controller.model.onNewNote = { [weak self] in self?.newNoteInWindow() }
        notch.settings.$hidesFromCapture
            .removeDuplicates()
            .sink { [weak controller] isHidden in controller?.setHiddenFromCapture(isHidden) }
            .store(in: &cancellables)
        window = controller
        return controller
    }

    /// "+ Note" in the window: a note in the folder shown there.
    private func newNoteInWindow() {
        Task {
            await flush()
            await store.newNote(in: store.selectedFolderID)
        }
    }

    /// Writes the raw (compressed) body of a note's database row to `file`; for automated checks. False when
    /// the note has no row key or the database cannot be read (no Full Disk Access).
    public func dumpNoteData(noteID: String, to file: URL) -> Bool {
        guard let key = NotesIDs.databaseKey(of: noteID, entity: "ICNote"),
              let data = NoteStoreReader().rawData(forNoteKey: key) else { return false }
        return (try? data.write(to: file)) != nil
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
        if isShowing {
            load(launching: true)
        } else {
            notch.setKeepsOpen(false, forPage: Self.pageID)
            Task { await flush() }
        }
    }

    /// The page's view appeared: lists again, starting Notes only when the page or the window is really showing.
    func pageAppeared() {
        load(launching: isPageShowing || isWindowShowing)
    }

    /// The window was shown or closed. Showing it counts as the page really showing: Notes is started if closed.
    /// Closing it saves what was typed.
    func windowShowingChanged(_ isShowing: Bool, noteID: String? = nil) {
        isWindowShowing = isShowing
        isWindowMiniaturized = false
        updateRefreshTimer(fullView: store.fullView)
        if isShowing {
            load(launching: true, noteID: noteID)
        } else {
            Task { await flush() }
        }
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
            } else if store.open == nil,
                      let first = NotesPageView.listed(store.notes, recent: settings.recentIDs, isSearching: false)
                        .first(where: { !$0.isLocked }) {
                await store.openNote(first.id)
            }
        }
    }

    /// The window went to the Dock (the timer pauses) or came back (lists again at once, and the timer resumes).
    func windowMiniaturizedChanged(_ isMiniaturized: Bool) {
        guard isWindowShowing, isMiniaturized != isWindowMiniaturized else { return }
        isWindowMiniaturized = isMiniaturized
        updateRefreshTimer(fullView: store.fullView)
        if !isMiniaturized, !store.fullView { Task { await refreshAfterChange(launchingNotes: false) } }
    }

    /// Refreshes every 30 seconds while the window is up (not in the Dock) and no database change can be watched.
    private func updateRefreshTimer(fullView: Bool) {
        guard isWindowShowing, !isWindowMiniaturized, !fullView else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.windowRefreshInterval, repeats: true) { [weak self] _ in
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
            guard let self, self.isPageShowing || self.isWindowShowing else { return }
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
