import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// The page's list: the notes found (the folder's, or what the search found) by date, as Notes groups them. A note
/// just deleted is offered for undo in a strip above the list.
struct NoteListColumn: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel

    var body: some View {
        VStack(spacing: 6 * ui) {
            if let deleted = model.deleted {
                undoStrip(deleted)
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
        .animation(AraTheme.settle, value: model.deleted)
    }

    private func title(of group: (titleKey: String, notes: [NoteSummary]), now: Date) -> String {
        guard group.titleKey == "notes.group.month", let date = group.notes.first?.modified else {
            return L10n.string(group.titleKey)
        }
        let month = NoteListGrouping.monthTitle(of: date, now: now, calendar: .current)
        return String(format: L10n.string("notes.group.month"), month)
    }

    private func undoStrip(_ deleted: DeletedNote) -> some View {
        HStack(spacing: 8 * ui) {
            AraIcon.delete.image
                .font(.system(size: 10 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.label)
            Text(String(format: L10n.string("notes.deleted"),
                        deleted.name.isEmpty ? L10n.string("notes.untitled") : deleted.name))
                .font(.system(size: AraType.footnote * ui, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if deleted.folderID != nil {
                // The name gives way; the button keeps its word.
                AraPillButton(L10n.string("notes.undo"), icon: .undo) {
                    Task { await model.undoDelete(in: store) }
                }
                .fixedSize()
                .layoutPriority(1)
            }
        }
        .padding(.leading, 10 * ui)
        .padding(.trailing, 6 * ui)
        .padding(.vertical, 6 * ui)
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
                    Task { await model.delete(note.id, in: store) }
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
                Task { await model.delete(note.id, in: store) }
            }
        }
    }

    private func open() {
        if note.isLocked {
            Task { await store.showInNotes(note.id) }
        } else if store.open?.id != note.id {
            NoteEditorCoordinator.commitAll()   // the open note's last keystrokes go with it
            Task { await store.openNote(note.id) }
        }
    }
}
