import ClipboardCore
import NotchShell
import SwiftUI

/// The symbols a board can use.
enum BoardSymbols {
    static let all = ["pin", "star", "briefcase", "chevron.left.forwardslash.chevron.right", "link", "heart"]
    static let fallback = "pin"
}

/// The row of chips next to the search field: All, each kind of clip with how many there
/// are, each board, the saved searches, and a button to add a board.
struct BoardChipsView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: ClipboardViewModel
    /// Boards are created and renamed on the notch page, which has the editor row.
    var allowsEditing = true
    @Environment(\.araHue) private var pageHue

    /// The chip that is lit, as the id it is scrolled to by: a row longer than the notch
    /// brings it into view, so what the page shows is always named on screen.
    static func chosenChip(boardID: Int64?, search: String, savedFilters: [String]) -> String {
        if let boardID { return "board:\(boardID)" }
        if savedFilters.contains(search) { return "filter:\(search)" }
        if let kind = ClipKindTally.kind(in: search) { return "kind:\(kind.rawValue)" }
        return "all"
    }

    private var chosenChip: String {
        Self.chosenChip(
            boardID: model.selectedBoardID, search: model.searchText, savedFilters: model.savedFilters.map(\.query))
    }

    var body: some View {
        ScrollViewReader { proxy in
            chipRow
                .onAppear { proxy.scrollTo(chosenChip, anchor: .center) }
                .onChange(of: chosenChip) { _, chip in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(chip, anchor: .center) }
                }
                // A board just made appears in the row a moment after it is chosen.
                .onChange(of: model.boards.map(\.id)) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(chosenChip, anchor: .center) }
                }
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5 * ui) {
                let tally = ClipKindTally(model.items)
                let narrowedTo = ClipKindTally.kind(in: model.searchText)
                chip(
                    title: L10n.string("clipboard.boards.all"), symbol: "tray.full", count: tally.total,
                    isSelected: model.selectedBoardID == nil && narrowedTo == nil
                ) {
                    model.onSelectBoard?(nil)
                    if let narrowedTo {
                        model.searchText = ClipKindTally.search(toggling: narrowedTo, in: model.searchText)
                    }
                }
                .id("all")

                // One click narrows the list to a kind, by typing its filter in the search;
                // a second click clears it. Each kind's chip takes that kind's colour.
                ForEach(tally.kinds, id: \.kind) { entry in
                    chip(
                        title: entry.kind.filterTitle, symbol: entry.kind.symbolName, count: entry.count,
                        isSelected: narrowedTo == entry.kind
                    ) {
                        model.searchText = ClipKindTally.search(toggling: entry.kind, in: model.searchText)
                    }
                    .araHue(entry.kind.hue ?? pageHue)
                    .id("kind:\(entry.kind.rawValue)")
                }

                ForEach(model.boards) { board in
                    ClipDropTarget { itemID in
                        model.onDropOnBoard?(itemID, board)
                    } content: { isTargeted in
                        chip(
                            title: board.name, symbol: symbol(for: board), count: board.itemCount,
                            isSelected: model.selectedBoardID == board.id
                        ) { model.onSelectBoard?(board.id) }
                        // The board a held clip would be pinned to says so.
                        .overlay(Capsule().strokeBorder(AraPalette.accent, lineWidth: isTargeted ? 1.5 * ui : 0))
                        .scaleEffect(isTargeted ? 1.08 : 1)
                        .animation(AraTheme.hover, value: isTargeted)
                    }
                    .contextMenu {
                        if allowsEditing {
                            Button(L10n.string("clipboard.boards.rename")) { model.onEditBoard?(board) }
                            Button(L10n.string(board.isLocked ? "clipboard.boards.unlock" : "clipboard.boards.lock")) {
                                model.onToggleBoardLock?(board)
                            }
                            Divider()
                            Button(L10n.string("clipboard.boards.delete"), role: .destructive) {
                                model.onDeleteBoard?(board)
                            }
                        }
                    }
                    .id("board:\(board.id)")
                }

                // Saved searches: one click types the search again; a second click clears it.
                ForEach(model.savedFilters) { filter in
                    chip(
                        title: filter.query, symbol: "line.3.horizontal.decrease.circle", count: nil,
                        isSelected: model.searchText == filter.query
                    ) {
                        model.onSelectBoard?(nil)
                        model.searchText = model.searchText == filter.query ? "" : filter.query
                    }
                    .contextMenu {
                        Button(L10n.string("clipboard.filters.remove"), role: .destructive) {
                            model.onRemoveFilter?(filter)
                        }
                    }
                    .id("filter:\(filter.query)")
                }

                if allowsEditing {
                    addButton
                }
            }
        }
    }

    /// A locked board shows a padlock, open or closed with the vault, instead of its own symbol.
    private func symbol(for board: ClipBoard) -> String {
        guard board.isLocked else { return board.symbolName }
        return model.vaultState == .unlocked ? "lock.open.fill" : "lock.fill"
    }

    private var addButton: some View {
        AraIconButton(.add, size: .small, help: L10n.string("clipboard.boards.new.tooltip")) {
            model.onBeginNewBoard?()
        }
    }

    private func chip(
        title: String, symbol: String, count: Int?, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        let label = HStack(spacing: 4 * ui) {
            Image(systemName: symbol)
                .font(.system(size: 10 * ui, weight: .medium))
            Text(title)
                .font(.system(size: 10 * ui, weight: .medium))
                .lineLimit(1)
            if let count {
                Text(count.formatted())
                    .font(.system(size: 10 * ui))
                    .foregroundStyle(.primary.opacity(0.5))
            }
        }
        return AraChip(isSelected: isSelected, action: action) { label }
    }
}

/// Replaces the top row while a board is being created or renamed.
struct BoardEditorView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: ClipboardViewModel
    let draft: ClipboardViewModel.BoardDraft

    var body: some View {
        HStack(spacing: 6 * ui) {
            ForEach(BoardSymbols.all, id: \.self) { symbol in
                Button {
                    model.boardDraft?.symbolName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 10 * ui, weight: .medium))
                        .frame(width: 22 * ui, height: 22 * ui)
                        .araSurface(Circle(), level: draft.symbolName == symbol ? .selected : .plate)
                        .contentShape(Circle())
                }
                .buttonStyle(AraPressStyle())
            }

            PanelSearchField(
                text: draft.name,
                placeholder: L10n.string("clipboard.boards.name.placeholder"),
                focusToken: model.boardEditorFocusToken,
                fontSize: 12
            ) { model.boardDraft?.name = $0 }
                .padding(.horizontal, 8 * ui)
                .frame(height: 24 * ui)
                .araSurface(Capsule())

            if let errorKey = draft.errorKey {
                Text(L10n.string(errorKey))
                    .font(.system(size: 10 * ui))
                    .foregroundStyle(AraPalette.danger)
                    .lineLimit(1)
                    .fixedSize()
            }

            AraIconButton(.confirm, look: .accent, size: .small, help: L10n.string("clipboard.boards.save")) {
                model.onCommitDraft?()
            }
            AraIconButton(.close, size: .small, help: L10n.string("settings.cancel")) { model.onCancelDraft?() }
        }
    }
}
