import AppKit
import ClipboardCore
import NotchShell
import SwiftUI

/// The right-click menu of a clip, shared by the notch page and the floating panel.
struct ClipContextMenu: View {
    let item: ClipItem
    @ObservedObject var model: ClipboardViewModel

    var body: some View {
        Button { model.onPaste?(item) } label: { label("clipboard.menu.paste", .paste) }
        if item.kind == .text || item.kind == .link {
            Button { model.onPastePlain?(item) } label: { label("clipboard.menu.pastePlain", .pastePlain) }
        }
        Button { model.onCopy?(item) } label: { label("clipboard.menu.copy", .copy) }
        if !item.isEncrypted {
            Button { model.onEdit?(item) } label: { label("clipboard.menu.edit", .edit) }
        }
        openItems
        if !model.boards.isEmpty {
            Menu {
                ForEach(model.boards) { board in
                    Button {
                        model.onTogglePin?(item, board)
                    } label: {
                        Label(
                            board.name,
                            systemImage: model.isPinned(item, to: board) ? "checkmark" : board.symbolName)
                    }
                }
            } label: { label("clipboard.menu.pinTo", .pin) }
        }
        if ClipboardViewModel.canTransform(item) {
            Menu {
                ForEach(Array(TextTransform.Group.allCases.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Divider()
                    }
                    ForEach(TextTransform.tools(in: group), id: \.self) { tool in
                        Button(L10n.string("clipboard.tools.\(tool.rawValue)")) { model.onTransform?(item, tool) }
                    }
                }
            } label: { label("clipboard.menu.tools", .pastePlain) }
        }
        if !model.assistantActions.isEmpty, item.kind == .text, !item.isEncrypted {
            Menu {
                ForEach(model.assistantActions, id: \.self) { action in
                    Button(L10n.string("clipboard.assist.\(action)")) { model.onAssist?(item, action) }
                }
            } label: { label("clipboard.menu.assist", .assistant) }
        }
        if item.kind == .image, !item.isEncrypted {
            Button { model.onRemoveBackground?(item) } label: { label("clipboard.menu.removeBackground", .removeBackground) }
            Menu {
                ForEach(["png", "jpeg", "heic"], id: \.self) { format in
                    Button(format.uppercased()) { model.onSaveImage?(item, format) }
                }
            } label: { label("clipboard.menu.saveImage", .savePicture) }
        }
        if model.canRemind, !item.isEncrypted {
            Menu {
                ForEach(ClipReminderPreset.allCases, id: \.self) { preset in
                    Button(L10n.string("clipboard.remind.\(preset.rawValue)")) { model.onRemind?(item, preset) }
                }
                Divider()
                Button(L10n.string("clipboard.remind.choose")) { model.onRemindAt?(item) }
            } label: { label("clipboard.menu.remind", .remind) }
        }
        if item.kind == .color, !item.isEncrypted {
            Menu {
                ForEach(ClipColor.Format.allCases, id: \.self) { format in
                    Button(format.rawValue.uppercased()) { model.onCopyColor?(item, format) }
                }
            } label: { label("clipboard.menu.copyColor", .color) }
        }
        Divider()
        Button(role: .destructive) { model.onDelete?(item) } label: { label("clipboard.menu.delete", .delete) }
    }

    /// A line of the menu: its words, and the icon the same action has everywhere else.
    private func label(_ key: String, _ icon: AraIcon) -> some View {
        Label(L10n.string(key), systemImage: icon.symbolName)
    }

    /// Open, Open With and Show in Finder, for clips that are a link, a file or an image.
    @ViewBuilder
    private var openItems: some View {
        if item.kind == .link, !item.isEncrypted {
            Button { model.onOpen?(item) } label: { label("clipboard.menu.openLink", .openLink) }
        }
        if let url = model.fileURL?(item) {
            Button { model.onOpen?(item) } label: { label("clipboard.menu.open", .open) }
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(10)
            if !apps.isEmpty {
                Menu {
                    ForEach(Array(apps), id: \.self) { app in
                        Button(FileManager.default.displayName(atPath: app.path)) { model.onOpenWith?(item, app) }
                    }
                } label: { label("clipboard.menu.openWith", .openWith) }
            }
            if item.kind == .file {
                Button { model.onReveal?(item) } label: { label("clipboard.menu.reveal", .showInFinder) }
            }
        }
        if item.kind == .image, let text = item.recognizedText, !text.isEmpty {
            Button { model.onCopyRecognizedText?(item) } label: { label("clipboard.menu.copyImageText", .readText) }
        }
    }
}
