import AppKit
import ClipboardCore
import NotchShell
import SwiftUI

/// The floating panel, one card: search on top, the history as a list, a large preview
/// of the selection.
struct ClipboardPanelView: View {
    static let size = CGSize(width: 560, height: 380)
    private static let listWidth: CGFloat = 250

    @ObservedObject var model: ClipboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let prompt = model.passcodePrompt {
                PasscodeRowView(model: model, prompt: prompt)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
            } else {
                searchRow
            }
            BoardChipsView(model: model, allowsEditing: false)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            separator
            HStack(spacing: 0) {
                list.frame(width: Self.listWidth)
                Rectangle().fill(AraPalette.hairline).frame(width: 1)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            separator
            if model.undoableDeletionCount > 0 {
                ClipUndoToast(model: model)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            } else {
                hint
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(AraTheme.settle, value: model.undoableDeletionCount)
        .araCard(radius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // The clipboard's colour, as on its page of the notch.
        .araHue(.peach)
    }

    private var separator: some View {
        Rectangle().fill(AraPalette.hairline).frame(height: 1)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AraPalette.label)
            PanelSearchField(
                text: model.searchText,
                placeholder: L10n.string("clipboard.search.placeholder"),
                focusToken: model.panelFocusToken
            ) { model.searchText = $0 }
            AraIconButton(
                model.isPanelPinned ? .unpin : .pin, size: .small, isOn: model.isPanelPinned,
                help: L10n.string("clipboard.panel.pin.tooltip")
            ) {
                model.isPanelPinned.toggle()
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        let items = model.pageItems
        if items.isEmpty {
            AraEmptyState(
                icon: emptyListKey == "clipboard.noResults" ? .search : .clipboard, title: L10n.string(emptyListKey))
                .padding(.horizontal, 12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                                .id(item.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection.selectedID) { _, selectedID in
                    if let selectedID {
                        proxy.scrollTo(selectedID)
                    }
                }
            }
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        let isSelected = item.id == model.selection.selectedID
        return PanelRow(isSelected: isSelected) { rowContent(item, index: index, isSelected: isSelected) }
            .onTapGesture(count: 2) { model.onPaste?(item) }
            .onTapGesture { model.select(item) }
            .draggable(as: item, model: model)
            .onClipDrop { itemID in model.onReorder?(itemID, item) }
            .contextMenu {
                ClipContextMenu(item: item, model: model)
            }
    }

    private func rowContent(_ item: ClipItem, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            rowIcon(item, isSelected: isSelected)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.rowTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                // Where it came from and when, as the card writes a fact: APP | when.
                HStack(spacing: 4) {
                    if model.isPinned(item) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7.5))
                            .foregroundStyle(AraPalette.label)
                    }
                    if let app = item.source.appName, !app.isEmpty {
                        AraFactRow(app, item.relativeTime)
                    } else {
                        Text(item.relativeTime)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AraPalette.value)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .opacity(isSelected ? 0.75 : 0.45)
            }
        }
    }

    private var emptyListKey: String {
        if model.items.isEmpty { return "clipboard.empty.title" }
        if model.selectedBoardID != nil, model.boardItems.isEmpty { return "clipboard.boards.empty.title" }
        return "clipboard.noResults"
    }

    @ViewBuilder
    private func rowIcon(_ item: ClipItem, isSelected: Bool) -> some View {
        if item.kind == .color {
            RoundedRectangle(cornerRadius: 4)
                .fill(item.swatch)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(AraPalette.hairline, lineWidth: 1))
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: CodeRecognition.isCode(item) ? "chevron.left.forwardslash.chevron.right" : item.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AraPalette.label(in: item.hue))
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let item = model.selectedItem {
            VStack(alignment: .leading, spacing: 8) {
                ClipPreviewView(item: item, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                metadata(item)
            }
            .padding(12)
        } else {
            Color.clear
        }
    }

    /// The facts about the clip, as the card writes them: APP | size · format · when.
    @ViewBuilder
    private func metadata(_ item: ClipItem) -> some View {
        let facts = [
            ClipFormatters.byteCount.string(fromByteCount: Int64(item.byteSize)),
            item.richFormatLabel,
            item.relativeTime,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        if let app = item.source.appName, !app.isEmpty {
            AraFactRow(app, facts)
        } else {
            Text(facts)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AraPalette.value)
                .lineLimit(1)
        }
    }

    /// The keys of the panel, each beside the icon of what it does; the words are in the tooltips.
    private var hint: some View {
        HStack(spacing: 12) {
            keyHint("↑↓", icon: nil, help: "clipboard.panel.key.select")
            keyHint("↩", icon: .paste, help: "clipboard.panel.key.paste")
            keyHint("⌥↩", icon: .pastePlain, help: "clipboard.panel.key.plain")
            keyHint("⌘↩", icon: .copy, help: "clipboard.panel.key.copy")
            keyHint("⌘⌫", icon: .delete, help: "clipboard.panel.key.delete")
            keyHint("space", icon: .preview, help: "clipboard.panel.key.preview")
            keyHint("⌘1–9", icon: .pin, help: "clipboard.panel.key.quick")
            keyHint("esc", icon: .close, help: "clipboard.panel.key.close")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .help(L10n.string("clipboard.panel.hint"))
    }

    private func keyHint(_ keys: String, icon: AraIcon?, help: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AraPalette.hairline, lineWidth: 1)
                }
            icon?.image
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(AraTheme.secondaryText)
        .help(L10n.string(help))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string(help))
    }
}

/// One row of the panel's list: the other palette's card when chosen, faintly filled under
/// the pointer.
private struct PanelRow<Content: View>: View {
    let isSelected: Bool
    let content: () -> Content
    @StateObject private var hover = AraHover()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Group {
            if isSelected {
                row.araSurface(shape, level: .selected)
            } else {
                row.background(AraPalette.ink.opacity(hover.isHovered ? 0.08 : 0), in: shape)
            }
        }
            .contentShape(Rectangle())
            .onHover { hover.isHovered = $0 }
            .animation(AraTheme.hover, value: hover.isHovered)
    }

    private var row: some View {
        content()
            .padding(.horizontal, 8)
            .frame(height: 38)
    }
}
