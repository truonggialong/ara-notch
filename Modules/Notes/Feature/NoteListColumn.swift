import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// The page's list: the notes found (the folder's, or what the search found) by date, as Notes groups them. A delete
/// is asked about in a card above the list, never in a system dialog.
struct NoteListColumn: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel

    var body: some View {
        VStack(spacing: 6 * ui) {
            if let id = model.deletingID, let note = store.notes.first(where: { $0.id == id }) {
                deleteConfirmation(note)
            }
            let notes = store.visibleNotes
            if notes.isEmpty {
                AraEmptyState(icon: store.searchText.isEmpty ? .document : .search,
                              title: L10n.string(store.searchText.isEmpty ? "notes.empty" : "notes.noResults"))
            } else {
                let now = Date()
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2 * ui) {
                        ForEach(Array(NoteListGrouping.groups(notes, now: now, calendar: .current).enumerated()), id: \.offset) { _, group in
                            AraLabel(title(of: group, now: now))
                                .padding(.horizontal, 7 * ui)
                                .padding(.top, 8 * ui)
                                .padding(.bottom, 1 * ui)
                            ForEach(group.notes) { note in NoteListRow(note: note, store: store, model: model) }
                        }
                    }
                }
                .araScrollFade()
            }
        }
        .animation(AraTheme.settle, value: model.deletingID)
    }

    private func title(of group: (titleKey: String, notes: [NoteSummary]), now: Date) -> String {
        guard group.titleKey == "notes.group.month", let date = group.notes.first?.modified else {
            return L10n.string(group.titleKey)
        }
        let month = NoteListGrouping.monthTitle(of: date, now: now, calendar: .current)
        return String(format: L10n.string("notes.group.month"), month)
    }

    private func deleteConfirmation(_ note: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 5 * ui) {
            Text(String(format: L10n.string("notes.delete.confirm"),
                        note.name.isEmpty ? L10n.string("notes.untitled") : note.name))
                .font(.system(size: AraType.footnote * ui, weight: .semibold))
                .lineLimit(2)
            Text(L10n.string("notes.delete.detail"))
                .font(.system(size: AraType.caption * ui))
                .opacity(0.68)
            HStack(spacing: 6 * ui) {
                Spacer(minLength: 0)
                AraPillButton(L10n.string("notes.cancel")) { model.cancelDelete() }
                AraPillButton(L10n.string("notes.delete"), icon: .delete, isDestructive: true) {
                    Task { await model.confirmDelete(in: store) }
                }
            }
        }
        .padding(9 * ui)
        .frame(maxWidth: .infinity, alignment: .leading)
        .araCard(radius: 10, level: .raised)
    }
}

/// One note of the list: its name, time, the start of its text and marks for pictures and a lock. Under the pointer
/// the marks give way to a delete button; a right click offers Show in Notes and Delete.
struct NoteListRow: View {
    @Environment(\.araScale) private var ui
    let note: NoteSummary
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel
    @StateObject private var hover = AraHover()

    var body: some View {
        HStack(spacing: 4 * ui) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 1 * ui) {
                    Text(note.name.isEmpty ? L10n.string("notes.untitled") : note.name)
                        .font(.system(size: AraType.body * ui, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 5 * ui) {
                        Text(NotesPageView.time(note.modified))
                            .font(.system(size: AraType.caption * ui, weight: .medium))
                        Text(note.snippet)
                            .font(.system(size: AraType.caption * ui))
                            .lineLimit(1)
                            .opacity(0.8)
                    }
                    .opacity(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(AraPressStyle(depth: 0.97))
            if hover.isHovered {
                AraIconButton(.delete, look: .bareDanger, size: .small, help: L10n.string("notes.delete")) {
                    model.askToDelete(note.id)
                }
            } else {
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
        }
        .padding(.leading, 7 * ui)
        .padding(.trailing, 4 * ui)
        .padding(.vertical, 4 * ui)
        .frame(maxWidth: .infinity, alignment: .leading)
        .araRow(isSelected: store.open?.id == note.id, radius: 8)
        .onHover { hover.isHovered = $0 }
        .contextMenu {
            Button(L10n.string("notes.showInNotes")) {
                Task { await store.showInNotes(note.id) }
            }
            Divider()
            Button(L10n.string("notes.delete"), role: .destructive) {
                model.askToDelete(note.id)
            }
        }
    }

    private func open() {
        model.cancelDelete()
        if note.isLocked {
            Task { await store.showInNotes(note.id) }
        } else if store.open?.id != note.id {
            NoteEditorCoordinator.commitAll()   // the open note's last keystrokes go with it
            Task { await store.openNote(note.id) }
        }
    }
}
