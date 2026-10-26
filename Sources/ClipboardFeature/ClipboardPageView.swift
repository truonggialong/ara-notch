import ClipboardCore
import NotchShell
import SwiftUI

/// The clipboard page of the notch: a search field above a row of history cards, newest first.
struct ClipboardPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: ClipboardViewModel

    var body: some View {
        VStack(spacing: 8 * ui) {
            topRow
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(AraTheme.settle, value: model.undoableDeletionCount)
    }

    /// Search and board chips; replaced by the board editor while a board is being named.
    @ViewBuilder
    private var topRow: some View {
        if let prompt = model.passcodePrompt {
            PasscodeRowView(model: model, prompt: prompt)
        } else if let draft = model.boardDraft {
            BoardEditorView(model: model, draft: draft)
        } else {
            HStack(spacing: 6 * ui) {
                searchField
                    .frame(width: 190 * ui)
                if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty,
                   !model.savedFilters.contains(where: { $0.query == model.searchText.trimmingCharacters(in: .whitespaces) }) {
                    AraIconButton(.saveFilter, size: .small) { model.onSaveFilter?() }
                }
                copyStackButton
                AraIconButton(.newNote, size: .small) { model.onNewNote?() }
                // For the seconds a deletion can be undone, the way back takes the boards' place.
                if model.undoableDeletionCount > 0 {
                    ClipUndoToast(model: model)
                    Spacer(minLength: 0 * ui)
                } else {
                    BoardChipsView(model: model)
                }
            }
        }
    }

    /// Starts or stops the copy stack; while it runs, shows how many clips wait in it.
    private var copyStackButton: some View {
        let stack = model.copyStack
        return AraIconButton(
            stack.isActive ? .copyStackOn : .copyStack, size: .small, isOn: stack.isActive,
            help: L10n.string("clipboard.copyStack.tooltip")
        ) {
            model.onToggleCopyStack?()
        }
        .overlay(alignment: .topTrailing) {
            if stack.isActive {
                Text(stack.count.formatted())
                    .font(.system(size: 8.5 * ui, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.ground)
                    .padding(.horizontal, 3.5 * ui)
                    .frame(minWidth: 13 * ui, minHeight: 13 * ui)
                    .background(AraPalette.value, in: Capsule())
                    .offset(x: 5 * ui, y: -4)
                    .allowsHitTesting(false)
            }
        }
        // Which clip is pasted first: chosen on the button itself, not in Settings.
        .contextMenu {
            ForEach(CopyStack.Order.allCases, id: \.self) { order in
                Button {
                    model.onSetCopyStackOrder?(order)
                } label: {
                    let title = L10n.string("settings.clipboard.copyStackOrder.\(order.rawValue)")
                    if model.copyStackOrder == order {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6 * ui) {
            AraIcon.search.image
                .foregroundStyle(AraTheme.tertiaryText)
            TextField(L10n.string("clipboard.search.short"), text: $model.searchText)
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
        .font(.system(size: 12 * ui))
        .padding(.horizontal, 9 * ui)
        .frame(height: 24 * ui)
        .araField()
        .help(L10n.string("clipboard.search.placeholder"))
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.storeError {
            message(title: L10n.string("clipboard.error.title"), body: error, icon: .warning)
        } else if model.items.isEmpty {
            message(
                title: L10n.string("clipboard.empty.title"),
                body: L10n.string("clipboard.empty.body"))
        } else if model.selectedBoardID != nil, model.boardItems.isEmpty {
            message(
                title: L10n.string("clipboard.boards.empty.title"),
                body: L10n.string("clipboard.boards.empty.body"), icon: .pin)
        } else if model.pageItems.isEmpty {
            message(title: L10n.string("clipboard.noResults"), body: nil, icon: .search)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8 * ui) {
                        ForEach(model.pageItems) { item in
                            card(for: item)
                                .id(item.id)
                        }
                    }
                    // Room for the selection outline and the lift under the pointer, which
                    // would otherwise be clipped.
                    .padding(.horizontal, 4 * ui)
                    .padding(.vertical, 3 * ui)
                }
                .onChange(of: model.selection.selectedID) { _, selectedID in
                    if model.showsSelectionInNotch, let selectedID {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(selectedID) }
                    }
                }
            }
        }
    }

    private func card(for item: ClipItem) -> some View {
        // The card under the pointer only changes tone; nothing moves, so nothing has to be
        // laid out again while the pointer travels along the row.
        AraHoverLift(scale: 1, dragProvider: { ClipDrag.provider(for: item, model: model) }) { isHovered in
            ClipCardView(
                item: item,
                thumbnail: model.thumbnail?(item),
                linkImage: model.linkImage?(item),
                isSelected: model.showsSelectionInNotch && item.id == model.selection.selectedID,
                isPinned: model.isPinned(item),
                isHovered: isHovered,
                isFlashed: model.flashedItemID == item.id,
                actions: item.isEncrypted ? nil : model)
        }
            .onTapGesture {
                model.flash(item)
                model.onPaste?(item)
            }
            .onClipDrop { itemID in model.onReorder?(itemID, item) }
            .contextMenu {
                ClipContextMenu(item: item, model: model)
            }
    }

    private func message(title: String, body: String?, icon: AraIcon = .clipboard) -> some View {
        AraEmptyState(icon: icon, title: title, detail: body)
    }
}
