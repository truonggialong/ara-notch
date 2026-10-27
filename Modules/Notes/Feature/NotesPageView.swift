import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// What the Notes page needs beside the store: whether access was looked at yet, what is under way on it (each of
/// which keeps the notch open), the handle the toolbar acts on the editor through, and the controller's actions.
@MainActor
final class NotesPageModel: ObservableObject {
    /// False until the first refresh, so the access card does not flash before Notes answered.
    @Published var hasChecked = false
    let editor = NoteEditorHandle()
    @Published var isEditorFocused = false { didSet { updateKeepsNotchOpen() } }
    @Published var isChoosingFolder = false { didSet { updateKeepsNotchOpen() } }
    @Published var isAddingFolder = false { didSet { updateKeepsNotchOpen() } }
    @Published var newFolderName = ""
    /// The note whose deletion waits to be confirmed.
    @Published var deletingID: String? { didSet { updateKeepsNotchOpen() } }
    /// True while the picture chooser is up: it takes the keyboard from the editor.
    @Published var isChoosingImages = false { didSet { updateKeepsNotchOpen() } }
    @Published private(set) var keepsNotchOpen = false
    var onAppear: (() -> Void)?
    var onEditorFocus: ((Bool) -> Void)?
    var onNewNote: (() -> Void)?

    private func updateKeepsNotchOpen() {
        let keeps = isEditorFocused || isChoosingFolder || isAddingFolder || deletingID != nil || isChoosingImages
        if keeps != keepsNotchOpen { keepsNotchOpen = keeps }
    }

    /// The page was left: what was open on it closes, and nothing keeps the notch any more.
    func closeWhatIsOpen() {
        isChoosingFolder = false
        isAddingFolder = false
        newFolderName = ""
        deletingID = nil
        isEditorFocused = false
    }
}

/// The Notes page of the notch: the recent notes on the left with search and "+", the open note's editor on the right.
struct NotesPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var settings: NotesSettings
    @ObservedObject var model: NotesPageModel

    var body: some View {
        Group {
            if model.hasChecked, store.access != .granted {
                NotesAccessCard(store: store)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 10 * ui) {
                        listColumn
                            .frame(width: (geometry.size.width * 0.38).rounded())
                        editorColumn
                    }
                }
            }
        }
        .onAppear { model.onAppear?() }
    }

    // MARK: List

    private var listColumn: some View {
        VStack(spacing: 6 * ui) {
            HStack(spacing: 6 * ui) {
                searchField
                AraIconButton(.add, size: .small, help: L10n.string("notes.new")) { model.onNewNote?() }
            }
            if model.hasChecked, !store.fullView {
                NotesFullViewCard()
            }
            let listed = Self.listed(store.visibleNotes, recent: settings.recentIDs, isSearching: !store.searchText.isEmpty)
            if listed.isEmpty {
                AraEmptyState(icon: store.searchText.isEmpty ? .document : .search,
                              title: L10n.string(store.searchText.isEmpty ? "notes.empty" : "notes.noResults"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2 * ui) {
                        ForEach(listed) { note in row(note) }
                    }
                }
                .araScrollFade()
            }
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
        .frame(height: 24 * ui)
        .araField()
    }

    private func row(_ note: NoteSummary) -> some View {
        Button {
            if note.isLocked {
                Task { await store.showInNotes(note.id) }
            } else {
                NoteEditorCoordinator.commitAll()   // the open note's last keystrokes go with it
                Task { await store.openNote(note.id) }
            }
        } label: {
            HStack(spacing: 5 * ui) {
                VStack(alignment: .leading, spacing: 1 * ui) {
                    Text(note.name.isEmpty ? L10n.string("notes.untitled") : note.name)
                        .font(.system(size: AraType.body * ui, weight: .medium))
                        .lineLimit(1)
                    Text(Self.time(note.modified))
                        .font(.system(size: AraType.caption * ui))
                        .opacity(0.6)
                }
                Spacer(minLength: 0)
                if note.hasImages {
                    AraIcon.picture.image
                        .font(.system(size: 10 * ui))
                        .opacity(0.6)
                        .help(L10n.string("notes.row.images"))
                }
                if note.isLocked {
                    AraIcon.locked.image
                        .font(.system(size: 10 * ui))
                        .opacity(0.6)
                        .help(L10n.string("notes.row.locked"))
                }
            }
            .padding(.horizontal, 7 * ui)
            .padding(.vertical, 4 * ui)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .araRow(isSelected: store.open?.id == note.id, radius: 8)
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
    }

    /// The notes opened lately first, in the order they were opened, then the rest newest first.
    /// A search lists what it found newest first.
    static func listed(_ notes: [NoteSummary], recent: [String], isSearching: Bool) -> [NoteSummary] {
        guard !isSearching else { return notes }
        let rank = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let (opened, rest) = notes.reduce(into: ([NoteSummary](), [NoteSummary]())) { result, note in
            if rank[note.id] != nil { result.0.append(note) } else { result.1.append(note) }
        }
        return opened.sorted { rank[$0.id]! < rank[$1.id]! } + rest
    }

    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Editor

    @ViewBuilder
    private var editorColumn: some View {
        VStack(spacing: 6 * ui) {
            NoteStatusBanner(store: store)
            if store.open != nil {
                NoteEditorView(store: store, imageSize: .thumbnail)
                    .handle(model.editor)
                    .focusChanged { model.onEditorFocus?($0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .araCard(radius: 12, level: .plate)
            } else {
                AraEmptyState(icon: .document, title: L10n.string("notes.none.title"),
                              detail: L10n.string("notes.none.detail"))
            }
        }
    }
}
