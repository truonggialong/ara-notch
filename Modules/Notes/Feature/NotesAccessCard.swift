import AppKit
import NotchShell
import SwiftUI

/// The two System Settings panes Notes needs.
enum NotesPrivacyPane {
    static let automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    static let fullDiskAccess = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    static func open(_ pane: String) {
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}

/// Shown in place of the Notes page until AraNotch may control Notes. Asks only from its Allow button.
struct NotesAccessCard: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore

    var body: some View {
        VStack(spacing: 8 * ui) {
            AraIcon.document.image
                .font(.system(size: 17 * ui, weight: .medium))
                .frame(width: 42 * ui, height: 42 * ui)
                .background(AraPalette.well, in: Circle())
            Text(L10n.string("notes.access.title"))
                .font(AraType.display(15 * ui))
            Text(L10n.string(store.access == .denied ? "notes.access.denied" : "notes.access.body"))
                .font(.system(size: AraType.footnote * ui))
                .opacity(0.68)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if store.access == .denied {
                AraPillButton(L10n.string("notes.access.openSettings"), isProminent: true) {
                    NotesPrivacyPane.open(NotesPrivacyPane.automation)
                }
            } else {
                AraPillButton(L10n.string("notes.access.allow"), isProminent: true) {
                    Task { await store.requestAccess() }
                }
            }
        }
        .padding(12 * ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small card in the list: without Full Disk Access some notes are read only and pictures may be missing.
struct NotesFullViewCard: View {
    @Environment(\.araScale) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * ui) {
            Text(L10n.string("notes.fullView.title"))
                .font(.system(size: AraType.footnote * ui, weight: .semibold))
            Text(L10n.string("notes.fullView.body"))
                .font(.system(size: AraType.caption * ui))
                .opacity(0.68)
                .lineLimit(3)
            AraPillButton(L10n.string("notes.fullView.open")) {
                NotesPrivacyPane.open(NotesPrivacyPane.fullDiskAccess)
            }
        }
        .padding(8 * ui)
        .frame(maxWidth: .infinity, alignment: .leading)
        .araCard(radius: 10, level: .raised)
    }
}
