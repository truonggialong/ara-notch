import AppKit
import NotchCore
import NotchShell
import NotesCore
import SwiftUI

/// What the Notes page needs beside the store: whether access was looked at yet, what is under way on it (each of
/// which keeps the notch open), the note just deleted (offered for undo), the handle the toolbar acts on the editor
/// through, and the controller's actions.
@MainActor
final class NotesPageModel: ObservableObject {
    /// False until the first refresh, so the access card does not flash before Notes answered.
    @Published var hasChecked = false
    let editor = NoteEditorHandle()
    @Published var isEditorFocused = false { didSet { updateKeepsNotchOpen() } }
    @Published var isChoosingFolder = false { didSet { updateKeepsNotchOpen() } }
    @Published var isAddingFolder = false { didSet { updateKeepsNotchOpen() } }
    @Published var newFolderName = ""
    /// The note just deleted, offered for undo for `undoTime`. It does not hold the notch open.
    @Published var deleted: DeletedNote?
    /// The delete under way: undo waits for it, so the note is in Recently Deleted when it is moved back.
    private var deleting: Task<DeletedNote?, Never>?
    static let undoTime: Duration = .seconds(10)
    private var undoExpiry: Task<Void, Never>?
    /// True while the picture chooser is up: it takes the keyboard from the editor.
    @Published var isChoosingImages = false { didSet { updateKeepsNotchOpen() } }
    @Published private(set) var keepsNotchOpen = false
    var onAppear: (() -> Void)?
    var onEditorFocus: ((Bool) -> Void)?
    var onNewNote: (() -> Void)?

    private func updateKeepsNotchOpen() {
        let keeps = isEditorFocused || isChoosingFolder || isAddingFolder || isChoosingImages
        if keeps != keepsNotchOpen { keepsNotchOpen = keeps }
    }

    /// Deletes a note: it leaves the page at once and undo is offered for a while, as Notes moves it to Recently
    /// Deleted. When Notes refuses, the note comes back, the offer goes and a beep tells.
    func delete(_ id: String, in store: NotesStore) async {
        NoteEditorCoordinator.commitAll()   // what was just typed goes with it, and comes back with undo
        let task = Task { await store.delete(id, started: { gone in self.offerUndo(gone) }) }
        deleting = task
        let gone = await task.value
        if deleting == task { deleting = nil }
        guard gone != nil else {
            if deleted?.id == id { deleted = nil }
            NSSound.beep()
            return
        }
        await store.refresh()
    }

    private func offerUndo(_ gone: DeletedNote) {
        deleted = gone
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.undoTime)
            guard !Task.isCancelled, self?.deleted == gone else { return }
            self?.deleted = nil
        }
    }

    /// Puts the note just deleted back; a failure is told by a beep.
    func undoDelete(in store: NotesStore) async {
        guard let gone = deleted else { return }
        deleted = nil
        undoExpiry?.cancel()
        if let deleting { _ = await deleting.value }
        if await !store.undoDelete(gone) { NSSound.beep() }
    }

    /// Shows the folder's notes (nil: all notes) and closes the folder list.
    func choose(folder id: String?, in store: NotesStore) async {
        isChoosingFolder = false
        guard store.selectedFolderID != id else { return }
        store.selectedFolderID = id
        await store.refresh()
    }

    /// Makes a folder of the name typed and shows it. False, with the name field left open, when the name is empty
    /// or Notes did not make it.
    func createFolder(in store: NotesStore) async -> Bool {
        guard await store.createFolder(named: newFolderName) != nil else { return false }
        isAddingFolder = false
        isChoosingFolder = false
        newFolderName = ""
        return true
    }

    /// Escape closes what is open on the page, the innermost first: the folder name, the folder list, the undo offer.
    /// False when nothing was (the notch then closes) and for every other key.
    func handleKey(_ key: NotchKey) -> Bool {
        guard key == .escape else { return false }
        if isAddingFolder {
            isAddingFolder = false
            newFolderName = ""
        } else if isChoosingFolder {
            isChoosingFolder = false
        } else if deleted != nil {
            deleted = nil
        } else {
            return false
        }
        return true
    }

    /// The page was left: what was open on it closes, and nothing keeps the notch any more.
    func closeWhatIsOpen() {
        isChoosingFolder = false
        isAddingFolder = false
        newFolderName = ""
        deleted = nil
        isEditorFocused = false
    }
}

/// The Notes page of the notch. Left: search and "+", the folder shown, and its notes by date. Right: the open note,
/// with a header (folder, time, whether it is saved, Show in Notes, Delete), the toolbar while it can be edited, and
/// the text.
struct NotesPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel

    var body: some View {
        Group {
            if model.hasChecked, store.access != .granted {
                NotesAccessCard(store: store)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 10 * ui) {
                        listColumn
                            .frame(width: (geometry.size.width * 0.3).rounded())
                        editorColumn
                    }
                }
            }
        }
        .onAppear { model.onAppear?() }
    }

    // MARK: List

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 4 * ui) {
            HStack(spacing: 6 * ui) {
                searchField
                AraIconButton(.add, look: .accent, help: L10n.string("notes.new")) { model.onNewNote?() }
            }
            .padding(.bottom, 2 * ui)
            NoteFolderPicker(store: store, model: model)
            ZStack(alignment: .top) {
                VStack(spacing: 6 * ui) {
                    if model.hasChecked, !store.fullView {
                        NotesFullViewCard()
                    }
                    NoteListColumn(store: store, model: model)
                }
                if model.isChoosingFolder {
                    NoteFolderList(store: store, model: model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(AraTheme.settle, value: model.isChoosingFolder)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6 * ui) {
            AraIcon.search.image
                .foregroundStyle(AraTheme.tertiaryText)
            TextField(L10n.string("notes.search"), text: $store.searchText)
                .textFieldStyle(.plain)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    AraIcon.clear.image
                        .foregroundStyle(AraTheme.tertiaryText)
                }
                .buttonStyle(AraPressStyle())
                .help(AraIcon.clear.label)
            }
        }
        .font(.system(size: 12 * ui))
        .padding(.horizontal, 9 * ui)
        .frame(height: 28 * ui)
        .araField()
    }

    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Editor

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            NoteStatusBanner(store: store)
            if let open = store.open {
                VStack(spacing: 0) {
                    NoteEditorHeader(store: store, model: model, open: open)
                    hairline
                    // Not on a note that cannot be edited (the banner says why). A read under way only greys it, so the
                    // text does not jump.
                    if NoteEditorCoordinator.isEditable(open, store.saveState, isReloading: false) {
                        FormatToolbar(handle: model.editor, isEnabled: !store.isReloading,
                                      onChoosingImages: { model.isChoosingImages = $0 })
                            .frame(maxWidth: .infinity, alignment: .leading)
                        hairline
                    }
                    GeometryReader { geometry in
                        // The text's insets and the line padding take about 34 pt of the width.
                        NoteEditorView(store: store, imageSize: .fitWidth(max(80, (geometry.size.width - 34 * ui).rounded(.down))))
                            .handle(model.editor)
                            .focusChanged { model.onEditorFocus?($0) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .araCard(radius: 12, level: .plate)
            } else {
                AraEmptyState(icon: .document, title: L10n.string("notes.none.title"),
                              detail: L10n.string("notes.none.detail"))
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(AraPalette.hairline)
            .frame(height: 1)
    }
}
