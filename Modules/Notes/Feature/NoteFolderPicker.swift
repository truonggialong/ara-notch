import AppKit
import NotchShell
import NotesCore
import SwiftUI

/// The title of the page's list: the folder shown and how many notes it has. A click opens the folder list.
struct NoteFolderPicker: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel

    var body: some View {
        let folder = store.folders.first { $0.id == store.selectedFolderID }
        Button {
            model.isChoosingFolder.toggle()
            if !model.isChoosingFolder { model.isAddingFolder = false }
        } label: {
            HStack(spacing: 5 * ui) {
                Image(systemName: folder == nil ? "tray.full" : "folder")
                    .font(.system(size: 10 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.label)
                Text(folder?.name ?? L10n.string("notes.allNotes"))
                    .font(.system(size: AraType.body * ui, weight: .semibold))
                    .lineLimit(1)
                Text((folder?.noteCount ?? store.folders.reduce(0) { $0 + $1.noteCount }).formatted())
                    .font(.system(size: AraType.caption * ui, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.value)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7 * ui, weight: .bold))
                    .foregroundStyle(AraPalette.label)
                    .rotationEffect(.degrees(model.isChoosingFolder ? 180 : 0))
            }
            .padding(.horizontal, 7 * ui)
            .frame(height: 22 * ui)
            .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle())
        .help(L10n.string("notes.chooseFolder"))
        .disabled(store.access != .granted)
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
}

/// The folder list, drawn inside the notch over the notes (a popover is a window of its own, and the pointer going
/// into it would close the notch): all notes, then each account's folders with their counts, and a new folder.
struct NoteFolderList: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var store: NotesStore
    @ObservedObject var model: NotesPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2 * ui) {
                    row(id: nil, name: L10n.string("notes.allNotes"), symbol: "tray.full",
                        count: store.folders.reduce(0) { $0 + $1.noteCount })
                    ForEach(NoteFolderPicker.accounts(of: store.folders), id: \.name) { account in
                        AraLabel(account.name)
                            .padding(.horizontal, 7 * ui)
                            .padding(.top, 8 * ui)
                            .padding(.bottom, 1 * ui)
                        ForEach(account.folders) { folder in
                            row(id: folder.id, name: folder.name, symbol: "folder", count: folder.noteCount)
                        }
                    }
                }
            }
            .araScrollFade()
            newFolder
        }
        .padding(6 * ui)
        .araCard(radius: 10, level: .raised)
        .animation(AraTheme.settle, value: model.isAddingFolder)
    }

    private func row(id: String?, name: String, symbol: String, count: Int) -> some View {
        Button {
            Task { await model.choose(folder: id, in: store) }
        } label: {
            HStack(spacing: 6 * ui) {
                Image(systemName: symbol)
                    .font(.system(size: 10 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.label)
                    .frame(width: 14 * ui)
                Text(name)
                    .font(.system(size: AraType.body * ui, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4 * ui)
                Text(count.formatted())
                    .font(.system(size: AraType.caption * ui, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.value)
            }
            .padding(.horizontal, 7 * ui)
            .frame(height: 24 * ui)
            .araRow(isSelected: store.selectedFolderID == id, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
    }

    @ViewBuilder
    private var newFolder: some View {
        if model.isAddingFolder {
            HStack(spacing: 4 * ui) {
                TextField(L10n.string("notes.folderName"), text: $model.newFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * ui))
                    .onSubmit(create)
                    .padding(.horizontal, 8 * ui)
                    .frame(height: 24 * ui)
                    .araField()
                AraIconButton(.confirm, look: .accent, size: .small, help: L10n.string("notes.createFolder"), action: create)
                AraIconButton(.close, look: .bare, size: .small, help: L10n.string("notes.cancel")) {
                    model.isAddingFolder = false
                    model.newFolderName = ""
                }
            }
        } else {
            AraPillButton(L10n.string("notes.newFolder"), icon: .add) {
                model.newFolderName = ""
                model.isAddingFolder = true
            }
        }
    }

    private func create() {
        Task {
            if await !model.createFolder(in: store) { NSSound.beep() }
        }
    }
}
