import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// What the Notes window keeps beside the store: its own search, the folder being named, the note waiting for
/// its deletion to be confirmed, and the handle its toolbar acts on the editor through.
@MainActor
final class NotesWindowModel: ObservableObject {
    let editor = NoteEditorHandle()
    @Published var searchText = ""
    @Published var isAddingFolder = false
    @Published var newFolderName = ""
    @Published var deletingID: String?
    var onNewNote: (() -> Void)?
}

/// The Notes window: folders by account on the left, the folder's notes by date in the middle, and the open note
/// with a fixed toolbar on the right. The open note is the store's, shared with the notch page.
struct NotesWindowView: View {
    static let size = CGSize(width: 1000, height: 640)
    static let minimumSize = CGSize(width: 720, height: 420)

    @ObservedObject var store: NotesStore
    @ObservedObject var page: NotesPageModel
    @ObservedObject var model: NotesWindowModel

    var body: some View {
        Group {
            if page.hasChecked, store.access != .granted {
                NotesAccessCard(store: store)
                    .frame(maxWidth: 420, maxHeight: 260)
                    .araCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 12) {
                    folderColumn
                        .frame(width: 210)
                        .araCard()
                    listColumn
                        .frame(width: 270)
                        .araCard()
                    editorColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(12)
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .foregroundStyle(AraPalette.onGround)
        .background(AraPalette.ground)
        .animation(AraTheme.settle, value: model.deletingID)
        .animation(AraTheme.settle, value: model.isAddingFolder)
    }

    // MARK: Folders

    private var folderColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    folderRow(id: nil, name: L10n.string("notes.window.allNotes"), symbol: "tray.full",
                              count: store.folders.reduce(0) { $0 + $1.noteCount })
                    ForEach(Self.accounts(of: store.folders), id: \.name) { account in
                        AraLabel(account.name)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 2)
                        ForEach(account.folders) { folder in
                            folderRow(id: folder.id, name: folder.name, symbol: "folder", count: folder.noteCount)
                        }
                    }
                }
            }
            .araScrollFade()
            if page.hasChecked, !store.fullView {
                NotesFullViewCard()
            }
            newFolder
        }
        .padding(8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            AraIcon.search.image
                .foregroundStyle(AraTheme.tertiaryText)
            TextField(L10n.string("notes.search"), text: $model.searchText)
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    AraIcon.clear.image
                        .foregroundStyle(AraTheme.tertiaryText)
                }
                .buttonStyle(AraPressStyle())
                .help(AraIcon.clear.label)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .araField()
    }

    /// Accounts in the order Notes lists their folders.
    static func accounts(of folders: [NoteFolder]) -> [(name: String, folders: [NoteFolder])] {
        var result: [(name: String, folders: [NoteFolder])] = []
        for folder in folders {
            if let index = result.firstIndex(where: { $0.name == folder.account }) {
                result[index].folders.append(folder)
            } else {
                result.append((folder.account, [folder]))
            }
        }
        return result
    }

    private func folderRow(id: String?, name: String, symbol: String, count: Int) -> some View {
        Button {
            guard store.selectedFolderID != id else { return }
            store.selectedFolderID = id
            model.deletingID = nil
            Task { await store.refresh() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AraPalette.label)
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(count.formatted())
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.value)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .araRow(isSelected: store.selectedFolderID == id)
            .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
    }

    @ViewBuilder
    private var newFolder: some View {
        if model.isAddingFolder {
            HStack(spacing: 4) {
                TextField(L10n.string("notes.window.folderName"), text: $model.newFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(createFolder)
                    .onExitCommand(perform: cancelFolder)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .araField()
                AraIconButton(.confirm, look: .accent, size: .small, help: L10n.string("notes.window.createFolder"),
                              action: createFolder)
                AraIconButton(.close, look: .bare, size: .small, help: L10n.string("notes.window.cancel"),
                              action: cancelFolder)
            }
        } else {
            AraPillButton(L10n.string("notes.window.newFolder"), icon: .add) {
                model.newFolderName = ""
                model.isAddingFolder = true
            }
            .disabled(store.access != .granted)
        }
    }

    private func createFolder() {
        let name = model.newFolderName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        Task {
            if await store.createFolder(named: name) != nil {
                model.isAddingFolder = false
                model.newFolderName = ""
            } else {
                NSSound.beep()
            }
        }
    }

    private func cancelFolder() {
        model.isAddingFolder = false
        model.newFolderName = ""
    }

    // MARK: Notes

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(store.folders.first { $0.id == store.selectedFolderID }?.name ?? L10n.string("notes.window.allNotes"))
                    .font(AraType.display(15))
                    .lineLimit(1)
                Spacer(minLength: 4)
                AraPillButton(L10n.string("notes.window.newNote"), icon: .add) { model.onNewNote?() }
                    .disabled(store.access != .granted)
            }
            .padding(.horizontal, 4)
            if let id = model.deletingID, let note = store.notes.first(where: { $0.id == id }) {
                deleteConfirmation(note)
            }
            let notes = NotesStore.filter(store.notes, searching: model.searchText)
            if notes.isEmpty {
                AraEmptyState(icon: model.searchText.isEmpty ? .document : .search,
                              title: L10n.string(model.searchText.isEmpty ? "notes.empty" : "notes.noResults"))
            } else {
                let now = Date()
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(NoteListGrouping.groups(notes, now: now, calendar: .current).enumerated()), id: \.offset) { _, group in
                            AraLabel(title(of: group, now: now))
                                .padding(.horizontal, 8)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                            ForEach(group.notes) { note in row(note) }
                        }
                    }
                }
                .araScrollFade()
            }
        }
        .padding(8)
    }

    private func title(of group: (titleKey: String, notes: [NoteSummary]), now: Date) -> String {
        guard group.titleKey == "notes.group.month", let date = group.notes.first?.modified else {
            return L10n.string(group.titleKey)
        }
        let month = NoteListGrouping.monthTitle(of: date, now: now, calendar: .current)
        return String(format: L10n.string("notes.group.month"), month)
    }

    private func row(_ note: NoteSummary) -> some View {
        Button {
            model.deletingID = nil
            if note.isLocked {
                Task { await store.showInNotes(note.id) }
            } else if store.open?.id != note.id {
                NoteEditorCoordinator.commitAll()   // the open note's last keystrokes go with it
                Task { await store.openNote(note.id) }
            }
        } label: {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.name.isEmpty ? L10n.string("notes.untitled") : note.name)
                        .font(.system(size: AraType.body, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(NotesPageView.time(note.modified))
                            .font(.system(size: AraType.caption, weight: .medium))
                        Text(note.snippet)
                            .font(.system(size: AraType.caption))
                            .lineLimit(1)
                            .opacity(0.8)
                    }
                    .opacity(0.6)
                }
                Spacer(minLength: 0)
                if note.hasImages {
                    AraIcon.picture.image
                        .font(.system(size: 10))
                        .opacity(0.6)
                        .help(L10n.string("notes.row.images"))
                }
                if note.isLocked {
                    AraIcon.locked.image
                        .font(.system(size: 10))
                        .opacity(0.6)
                        .help(L10n.string("notes.row.locked"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .araRow(isSelected: store.open?.id == note.id)
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
        .contextMenu {
            Button(L10n.string("notes.window.showInNotes")) {
                Task { await store.showInNotes(note.id) }
            }
            Divider()
            Button(L10n.string("notes.window.delete"), role: .destructive) {
                model.deletingID = note.id
            }
        }
    }

    /// Asked here, in the list, never in a system dialog.
    private func deleteConfirmation(_ note: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: L10n.string("notes.window.delete.confirm"),
                        note.name.isEmpty ? L10n.string("notes.untitled") : note.name))
                .font(.system(size: AraType.footnote, weight: .semibold))
                .lineLimit(2)
            Text(L10n.string("notes.window.delete.detail"))
                .font(.system(size: AraType.caption))
                .opacity(0.68)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                AraPillButton(L10n.string("notes.window.cancel")) { model.deletingID = nil }
                AraPillButton(L10n.string("notes.window.delete"), icon: .delete, isDestructive: true) {
                    let id = note.id
                    model.deletingID = nil
                    Task {
                        await store.delete(id)
                        await store.refresh()
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .araCard(radius: 10, level: .raised)
    }

    // MARK: Editor

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormatToolbar(handle: model.editor, isEnabled: NoteEditorCoordinator.isEditable(store.open, store.saveState, isReloading: store.isReloading))
            NoteStatusBanner(store: store)
            if store.open != nil {
                GeometryReader { geometry in
                    // The text's insets and the line padding take about 20 pt of the width.
                    NoteEditorView(store: store, imageSize: .fitWidth(max(80, (geometry.size.width - 20).rounded(.down))))
                        .handle(model.editor)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .araCard()
            } else {
                AraEmptyState(icon: .document, title: L10n.string("notes.none.title"),
                              detail: L10n.string("notes.window.none.detail"))
                    .araCard()
            }
        }
    }
}
