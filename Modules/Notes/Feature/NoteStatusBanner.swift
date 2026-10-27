import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// The strip above the editor (notch page and window alike) that says why the note cannot be edited
/// or was not saved, with what can be done about it.
struct NoteStatusBanner: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore

    var body: some View {
        if store.caughtUp, store.open.flatMap({ Self.content(open: $0, state: store.saveState) }) == nil {
            HStack(spacing: 8 * ui) {
                AraIcon.done.image
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.accent)
                Text(L10n.string("notes.banner.caughtUp"))
                    .font(.system(size: AraType.footnote * ui))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10 * ui)
            .padding(.vertical, 6 * ui)
            .araCard(radius: 10, level: .raised)
        } else if let open = store.open, let content = Self.content(open: open, state: store.saveState) {
            HStack(spacing: 8 * ui) {
                AraIcon.warning.image
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.warning)
                Text(content.message)
                    .font(.system(size: AraType.footnote * ui))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(content.actions, id: \.self) { action in
                    AraPillButton(L10n.string(action.titleKey)) { perform(action, open: open) }
                }
            }
            .padding(.horizontal, 10 * ui)
            .padding(.vertical, 6 * ui)
            .araCard(radius: 10, level: .raised)
        }
    }

    enum Action: Hashable {
        case reload, copyMine, copy, recreate, showInNotes

        var titleKey: String {
            switch self {
            case .reload: "notes.banner.reload"
            case .copyMine: "notes.banner.copyMine"
            case .copy: "notes.banner.copy"
            case .recreate: "notes.banner.recreate"
            case .showInNotes: "notes.banner.showInNotes"
            }
        }
    }

    struct Content: Equatable {
        var message: String
        var actions: [Action]
    }

    /// What the strip says for a note in a given state; nil when there is nothing to say.
    static func content(open: OpenNote, state: NoteSaveState) -> Content? {
        switch state {
        case .conflict:
            return Content(message: L10n.string("notes.banner.conflict"), actions: [.reload, .copyMine])
        case .deleted:
            return Content(message: L10n.string("notes.banner.deleted"), actions: [.copy, .recreate])
        case .failed(let message):
            return Content(message: L10n.string("notes.banner.failed") + " " + message, actions: [.copy])
        case .saved, .pending, .saving:
            guard case .readOnly(let reasons) = open.safety else { return nil }
            let why = reasons.map { L10n.string("notes.readOnly.\(key(of: $0))") }.joined(separator: ", ")
            return Content(message: L10n.string("notes.readOnly.title") + " " + why, actions: [.showInNotes])
        }
    }

    static func key(of reason: ReadOnlyReason) -> String {
        switch reason {
        case .checklist: "checklist"
        case .numberedList: "numberedList"
        case .quote: "quote"
        case .file: "file"
        case .drawing: "drawing"
        case .locked: "locked"
        case .listsUnknown: "listsUnknown"
        case .imagesUnavailable: "imagesUnavailable"
        case .unreadable: "unreadable"
        }
    }

    private func perform(_ action: Action, open: OpenNote) {
        // The editor's last keystrokes first: "mine" is what is on screen.
        NoteEditorCoordinator.commitAll()
        let document = store.open?.document ?? open.document
        switch action {
        case .reload:
            Task { await store.reloadOpenNote() }
        case .copyMine, .copy:
            let text = document.plainText.replacingOccurrences(of: "\u{FFFC}", with: "")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .recreate:
            Task { await store.newNote(document) }
        case .showInNotes:
            Task { await store.showInNotes(open.id) }
        }
    }
}
