import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// The row over the open note: its folder, when it was changed, whether it is saved, and the buttons to show it in
/// Notes and to delete it (asked about in the card over the list).
struct NoteEditorHeader: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel
    let open: OpenNote

    /// What the header says of the note. The banner under it says why, and what can be done.
    enum Status: Equatable {
        case saved, saving, viewOnly, notSaved, deleted, loading

        var titleKey: String {
            switch self {
            case .saved: "notes.status.saved"
            case .saving: "notes.status.saving"
            case .viewOnly: "notes.status.viewOnly"
            case .notSaved: "notes.status.notSaved"
            case .deleted: "notes.status.deleted"
            case .loading: "notes.status.loading"
            }
        }

        var symbol: String? {
            switch self {
            case .saved: "checkmark"
            case .viewOnly: "lock.fill"
            case .notSaved, .deleted: "exclamationmark.triangle.fill"
            case .saving, .loading: nil
            }
        }

        var isTrouble: Bool { self == .notSaved || self == .deleted }
    }

    /// What went wrong comes first, then a read under way, then whether the note can be edited at all.
    static func status(open: OpenNote, state: NoteSaveState, isReloading: Bool) -> Status {
        switch state {
        case .deleted: return .deleted
        case .conflict, .failed: return .notSaved
        case .saved, .pending, .saving: break
        }
        if isReloading { return .loading }
        if open.safety != .editable { return .viewOnly }
        return state == .saved ? .saved : .saving
    }

    var body: some View {
        let status = Self.status(open: open, state: store.saveState, isReloading: store.isReloading)
        HStack(spacing: 7 * ui) {
            if let folder = folderName {
                HStack(spacing: 4 * ui) {
                    Image(systemName: "folder")
                        .font(.system(size: 9 * ui, weight: .semibold))
                    Text(folder)
                        .lineLimit(1)
                }
                .font(.system(size: AraType.caption * ui, weight: .semibold))
                .foregroundStyle(AraPalette.ink.opacity(0.8))
                .padding(.horizontal, 7 * ui)
                .frame(height: 18 * ui)
                .background(Capsule().fill(AraPalette.well))
                .frame(maxWidth: 120 * ui, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            }
            Text(String(format: L10n.string("notes.header.modified"), NotesPageView.time(open.openedAt)))
                .font(.system(size: AraType.caption * ui, weight: .medium))
                .foregroundStyle(AraPalette.label)
                .lineLimit(1)
            HStack(spacing: 3 * ui) {
                if let symbol = status.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 8.5 * ui, weight: .bold))
                }
                Text(L10n.string(status.titleKey))
                    .lineLimit(1)
            }
            .font(.system(size: AraType.caption * ui, weight: .semibold))
            .foregroundStyle(status.isTrouble ? AraPalette.warning : AraPalette.label)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4 * ui)
            AraIconButton(.open, look: .bare, size: .small, help: L10n.string("notes.showInNotes")) {
                NoteEditorCoordinator.commitAll()
                Task { await store.showInNotes(open.id) }
            }
            if status != .deleted {
                AraIconButton(.delete, look: .bareDanger, size: .small, help: L10n.string("notes.delete")) {
                    model.askToDelete(open.id)
                }
            }
        }
        .padding(.leading, 12 * ui)
        .padding(.trailing, 6 * ui)
        .frame(height: 30 * ui)
    }

    /// The folder the open note is in, when a list has shown it.
    private var folderName: String? {
        guard let folderID = store.folderID(of: open.id) else { return nil }
        return store.folders.first { $0.id == folderID }?.name
    }
}
