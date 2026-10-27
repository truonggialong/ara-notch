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

    let store: NotesStore
    private let settings: NotesSettings
    private let notch: NotchController
    private let model = NotesPageModel()
    private let watchURL: URL?
    private var watcher: NoteStoreWatcher?
    private var cancellables: Set<AnyCancellable> = []
    private var isPageShowing = false

    /// Opens the Notes window on a note (nil: the open one). Set by the window (Task 11); until then the note
    /// is shown on the notch page.
    var onShowWindow: ((String?) -> Void)?

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

    /// Makes an empty note in the default folder and opens it.
    public func newNote() {
        Task {
            await flush()
            let before = store.open?.generation
            await store.newNote()
            // Nothing new opened: the note could not be made (no folder, no access).
            guard let id = store.open?.id, store.open?.generation != before else { return }
            showWindow(noteID: id)
        }
    }

    /// Opens the Notes window on a note. Until the window exists (Task 11) the note opens on the notch page.
    public func showWindow(noteID: String? = nil) {
        if let onShowWindow {
            onShowWindow(noteID)
            return
        }
        notch.selectPage(id: Self.pageID)
        notch.open()
        if let noteID, store.open?.id != noteID {
            Task { await store.openNote(noteID) }
        }
    }

    /// The `.newNote` shortcut is left to the app wiring (Task 12): ShortcutCenter keeps one handler per action,
    /// and Clipboard holds this one until then.
    public func start() {
        notch.setSheetHeight(Self.sheetHeight, forPage: Self.pageID)
        // Leaving the page, closing the notch or leaving the app saves what was typed.
        Publishers.CombineLatest(notch.isOpenPublisher, notch.selectedPagePublisher)
            .map { isOpen, page in isOpen && page == Self.pageID }
            .removeDuplicates()
            .sink { [weak self] isShowing in
                guard let self else { return }
                self.isPageShowing = isShowing
                if !isShowing {
                    self.notch.setKeepsOpen(false, forPage: Self.pageID)
                    Task { await self.flush() }
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in Task { await self?.flush() } }
            .store(in: &cancellables)
        // With Full Disk Access, Notes' own writes show while the page is up.
        store.$fullView
            .removeDuplicates()
            .sink { [weak self] fullView in self?.watch(fullView) }
            .store(in: &cancellables)
    }

    /// Hands the editor's last keystrokes to the store and waits until they are written.
    func flush() async {
        NoteEditorCoordinator.commitAll()
        await store.flush()
    }

    // MARK: Refreshing

    private func pageAppeared() {
        Task {
            await refreshAfterChange()
            model.hasChecked = true
            // Something to show: the latest note opened here, or else the newest one, when it can be opened.
            if store.open == nil, store.access == .granted,
               let first = NotesPageView.listed(store.notes, recent: settings.recentIDs, isSearching: false)
                .first(where: { !$0.isLocked }) {
                await store.openNote(first.id)
            }
        }
    }

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
            Task { await self.refreshAfterChange() }
        }
    }

    /// Lists the notes again, and reads the open note again when it changed in Notes and nothing typed here
    /// waits to be saved (AraNotch's own writes move `openedAt` along, so they do not count).
    private func refreshAfterChange() async {
        await store.refresh()
        guard let open = store.open, store.saveState == .saved,
              let summary = store.notes.first(where: { $0.id == open.id }),
              summary.modified.timeIntervalSince(open.openedAt) > 1 else { return }
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
