import AppKit
import ClipboardCore
import Combine
import NotchShell
import SwiftUI

/// What the Library window shows; kept in an object because `@State` is unavailable (see
/// `ClipboardSettingsSectionState`).
@MainActor
final class LibraryModel: ObservableObject {
    enum Layout: String {
        case grid
        case list
    }

    @Published var filter: LibraryFilter = .all
    @Published var layout: Layout = .grid
    @Published var searchText = ""
    /// Click selects one clip, Command-click adds or removes, Shift-click selects a range.
    @Published var selection = ClipMultiSelection()
    /// Each click adds a clip to the selection or takes it out, with no key held.
    @Published var isSelectingSeveral = false

    /// The clips the window lists now, top to bottom: the filter and the search applied.
    func visibleItems(of model: ClipboardViewModel) -> [ClipItem] {
        let sidebar = LibrarySidebar(items: model.items, boards: model.boards, membership: model.membership)
        // A filter whose last clip or board is gone falls back to everything.
        return Self.items(for: sidebar.contains(filter) ? filter : .all, search: searchText, model: model)
    }

    /// A locked board's clips are not in the plain history: they are the board's own, once the
    /// vault is open and the board chosen; until then, none.
    static func items(for filter: LibraryFilter, search: String, model: ClipboardViewModel) -> [ClipItem] {
        if case .board(let id) = filter, let board = model.boards.first(where: { $0.id == id }), board.isLocked {
            guard model.vaultState == .unlocked, model.selectedBoardID == id else { return [] }
            return LibraryFilter.all.items(from: model.sortOrder.sorted(model.boardItems), membership: model.membership, search: search)
        }
        return filter.items(from: model.sortOrder.sorted(model.items), membership: model.membership, search: search)
    }

    /// The locked board chosen while the vault is closed, if any.
    func lockedBoard(of model: ClipboardViewModel) -> ClipBoard? {
        guard case .board(let id) = filter, model.vaultState != .unlocked else { return nil }
        return model.boards.first { $0.id == id && $0.isLocked }
    }
}

/// The Library window: on the theme's ground, a card of filters on the left, the clips as a
/// grid or a list in the middle, and a card of details on the right.
struct LibraryView: View {
    static let size = CGSize(width: 940, height: 580)
    static let minimumSize = CGSize(width: 760, height: 420)
    /// Three cards a row at the window's usual width.
    static let gridCardMinimumWidth: CGFloat = 128

    @ObservedObject var model: ClipboardViewModel
    @ObservedObject var library: LibraryModel

    var body: some View {
        let sidebar = LibrarySidebar(items: model.items, boards: model.boards, membership: model.membership)
        // A filter whose last clip or board is gone falls back to everything.
        let filter = sidebar.contains(library.filter) ? library.filter : .all
        let items = LibraryModel.items(for: filter, search: library.searchText, model: model)
        // Clips that left the list drop out of the selection; with none left, the first is shown.
        let order = items.map(\.id)
        var selection = library.selection
        let _ = selection.sync(with: order)
        let selectedIDs = selection.ids.isEmpty ? Set(order.prefix(1)) : selection.ids
        let primary = items.first { $0.id == selection.primary } ?? items.first { selectedIDs.contains($0.id) }

        HStack(spacing: 12) {
            sidebarColumn(sidebar, selected: filter)
                .frame(width: 190)
                .araCard()
            VStack(spacing: 8) {
                toolbar
                content(items, selectedIDs: selectedIDs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            inspector(primary, selected: items.filter { selectedIDs.contains($0.id) })
                .frame(width: 270)
                .araCard()
        }
        .padding(12)
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .foregroundStyle(AraPalette.onGround)
        .animation(AraTheme.settle, value: model.undoableDeletionCount)
        .background(AraPalette.ground)
        // The clipboard's colour, as on its page of the notch.
        .araHue(.peach)
    }

    // MARK: - Sidebar

    private func sidebarColumn(_ sidebar: LibrarySidebar, selected: LibraryFilter) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(
                    .init(filter: .all, title: L10n.string("library.all"), symbolName: "tray.full", count: sidebar.total),
                    selected: selected)
                sidebarSection("library.section.kinds", sidebar.kinds.map { entry in
                    var entry = entry
                    if case .kind(let kind) = entry.filter {
                        entry.title = L10n.string("library.kind.\(kind.rawValue)")
                        entry.symbolName = kind.symbolName
                    }
                    return entry
                }, selected: selected)
                sidebarSection("library.section.apps", sidebar.apps.map { entry in
                    var entry = entry
                    entry.symbolName = "app"
                    return entry
                }, selected: selected)
                sidebarSection("library.section.boards", sidebar.boards, selected: selected)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func sidebarSection(_ titleKey: String, _ entries: [LibrarySidebar.Entry], selected: LibraryFilter) -> some View {
        if !entries.isEmpty {
            AraLabel(L10n.string(titleKey))
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 2)
            ForEach(entries) { entry in
                sidebarRow(entry, selected: selected)
            }
        }
    }

    private func sidebarRow(_ entry: LibrarySidebar.Entry, selected: LibraryFilter) -> some View {
        let isSelected = entry.filter == selected
        return Button {
            library.filter = entry.filter
            // A locked board asks for the passcode, as on the notch; an open one is shown.
            if entry.isLocked, case .board(let id) = entry.filter {
                model.onSelectBoard?(id)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: entry.isLocked
                    ? (model.vaultState == .unlocked ? "lock.open.fill" : "lock.fill")
                    : entry.symbolName ?? "square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AraPalette.label(in: Self.hue(of: entry.filter)))
                    .frame(width: 16)
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.count.formatted())
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.value)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .araRow(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
    }

    /// A kind of clip is listed in that kind's colour; everything else in the window's.
    private static func hue(of filter: LibraryFilter) -> AraHue? {
        if case .kind(let kind) = filter, let hue = kind.hue { return hue }
        return .peach
    }


    // MARK: - Toolbar and content

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AraPalette.label)
                TextField(L10n.string("clipboard.search.placeholder"), text: $library.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .araField()
            if model.undoableDeletionCount > 0 {
                ClipUndoToast(model: model)
            }
            // The order of the history; it used to be a setting, it is chosen where it is seen.
            Menu {
                ForEach(ClipSortOrder.allCases, id: \.self) { order in
                    Button {
                        model.onSetSortOrder?(order)
                    } label: {
                        let title = L10n.string("settings.clipboard.sortOrder.\(order.rawValue)")
                        if model.sortOrder == order {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.string("clipboard.library.sort"))
            .accessibilityLabel(L10n.string("clipboard.library.sort"))
            // Choosing several clips by clicks alone, for those who would rather not hold a key.
            AraIconButton(
                .completed, isOn: library.isSelectingSeveral, help: L10n.string("clipboard.library.selectSeveral")
            ) {
                library.isSelectingSeveral.toggle()
            }
            // The two ways to lay the clips out: the one in use is filled.
            HStack(spacing: 4) {
                AraIconButton(.grid, isOn: library.layout == .grid) { library.layout = .grid }
                AraIconButton(.list, isOn: library.layout == .list) { library.layout = .list }
            }
            .padding(3)
            .araSurface(Capsule())
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private func content(_ items: [ClipItem], selectedIDs: Set<Int64>) -> some View {
        if let board = library.lockedBoard(of: model) {
            lockedBoardView(board)
        } else if items.isEmpty {
            AraEmptyState(
                icon: model.items.isEmpty ? .clipboard : .search,
                title: L10n.string(model.items.isEmpty ? "clipboard.empty.title" : "clipboard.noResults"),
                detail: model.items.isEmpty ? L10n.string("clipboard.empty.body") : nil)
        } else {
            ScrollView {
                switch library.layout {
                case .grid:
                    LazyVGrid(
                        // Cards take the width of their column, so the columns fill the window
                        // whatever its width, with no gap between them.
                        columns: [GridItem(.adaptive(minimum: Self.gridCardMinimumWidth), spacing: 10)], spacing: 10
                    ) {
                        ForEach(items) { item in
                            clip(item, in: items) {
                                ClipCardView(
                                    item: item, thumbnail: model.thumbnail?(item), linkImage: model.linkImage?(item),
                                    isSelected: selectedIDs.contains(item.id), isPinned: model.isPinned(item),
                                    fillsWidth: true)
                            }
                        }
                    }
                    .padding(3)
                case .list:
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            clip(item, in: items) { listRow(item, isSelected: selectedIDs.contains(item.id)) }
                        }
                    }
                    .padding(6)
                    .araCard()
                    .padding(3)
                }
            }
        }
    }

    /// A locked board while the vault is closed: the passcode row, or a button that asks for it.
    private func lockedBoardView(_ board: ClipBoard) -> some View {
        VStack(spacing: 14) {
            AraEmptyState(
                icon: .locked, title: board.name,
                detail: L10n.string("clipboard.library.locked"))
                .frame(height: 150)
            if let prompt = model.passcodePrompt {
                PasscodeRowView(model: model, prompt: prompt, submitsOnReturn: true)
                    .frame(maxWidth: 360)
            } else {
                AraPillButton(L10n.string("clipboard.vault.unlock"), icon: .unlocked, isProminent: true) {
                    model.onSelectBoard?(board.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Click selects (with Command or Shift, several); right-click opens the clip menu.
    /// Dragging a selected clip carries the whole selection.
    private func clip(_ item: ClipItem, in items: [ClipItem], @ViewBuilder label: () -> some View) -> some View {
        label()
            // One click gesture only. A double-click gesture beside it would hold every click
            // back for the double-click interval, and by then Command or Shift may be released.
            .onTapGesture {
                // The click's own modifiers, not the keyboard's state a moment later.
                let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                var selection = library.selection
                selection.sync(with: items.map(\.id))
                selection.click(
                    item.id, in: items.map(\.id),
                    extending: modifiers.contains(.shift),
                    toggling: modifiers.contains(.command) || library.isSelectingSeveral)
                library.selection = selection
            }
            .onDrag {
                let ids = library.selection.dragged(from: item.id, in: items.map(\.id))
                return ClipDrag.provider(for: items.filter { ids.contains($0.id) }, model: model)
            }
            .contextMenu { ClipContextMenu(item: item, model: model) }
    }

    private func listRow(_ item: ClipItem, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AraPalette.label(in: item.hue))
                .frame(width: 18)
            Text(item.rowTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if model.isPinned(item) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(AraPalette.label)
            }
            Spacer(minLength: 8)
            if let app = item.source.appName, !app.isEmpty {
                AraFactRow(app, item.relativeTime)
            } else {
                Text(item.relativeTime)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AraPalette.value)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .araRow(isSelected: isSelected)
        .contentShape(Rectangle())
    }

    // MARK: - Inspector

    @ViewBuilder
    private func inspector(_ item: ClipItem?, selected: [ClipItem]) -> some View {
        if selected.count > 1 {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 28))
                    .foregroundStyle(AraPalette.label)
                Text(String(format: L10n.string("library.selected.count"), selected.count))
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.string("library.selected.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
                if !model.boards.isEmpty {
                    Menu {
                        ForEach(model.boards) { board in
                            Button {
                                selected.forEach { model.onDropOnBoard?($0.id, board) }
                            } label: {
                                Label(board.name, systemImage: board.symbolName)
                            }
                        }
                    } label: {
                        Label(L10n.string("clipboard.menu.pinTo"), systemImage: AraIcon.pin.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    // The outline goes round the menu, not inside its label: a borderless
                    // menu draws only the label's text and icon. Like the app's own buttons.
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .araSurface(Capsule())
                }
                HStack(spacing: 8) {
                    AraIconButton(.copy, look: .accent, size: .large, help: L10n.string("library.selected.copyText")) {
                        model.onCopyCombined?(selected)
                    }
                    AraIconButton(.delete, look: .danger, size: .large, help: L10n.string("clipboard.menu.delete")) {
                        selected.forEach { model.onDelete?($0) }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let item {
            VStack(alignment: .leading, spacing: 10) {
                ClipPreviewView(item: item, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(AraPalette.hairline).frame(height: 1)
                // The facts about the clip: a quiet caption, then the fact.
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(details(of: item), id: \.label) { detail in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(detail.label)
                                .font(.system(size: 11))
                                .foregroundStyle(AraPalette.label)
                                .frame(width: 74, alignment: .leading)
                            Text(detail.value)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                        }
                    }
                }
                HStack(spacing: 8) {
                    AraIconButton(.copy, look: .accent, help: L10n.string("clipboard.menu.copy")) { model.onCopy?(item) }
                    AraIconButton(.paste, help: L10n.string("clipboard.menu.paste")) { model.onPaste?(item) }
                    if !item.isEncrypted {
                        AraIconButton(.edit, help: L10n.string("clipboard.menu.edit")) { model.onEdit?(item) }
                    }
                    Spacer()
                    AraIconButton(.delete, look: .danger, help: L10n.string("clipboard.menu.delete")) { model.onDelete?(item) }
                }
            }
            .padding(12)
        } else {
            Color.clear
        }
    }

    private func details(of item: ClipItem) -> [(label: String, value: String)] {
        let boards = model.boards.filter { model.isPinned(item, to: $0) }.map(\.name)
        let rows: [(String, String?)] = [
            ("library.info.kind", L10n.string("library.kind.\(item.kind.rawValue)")),
            ("library.info.source", item.source.appName),
            ("library.info.created", Self.dateFormatter.string(from: item.createdAt)),
            ("library.info.lastUsed", Self.dateFormatter.string(from: item.lastUsedAt)),
            ("library.info.size", ClipFormatters.byteCount.string(fromByteCount: Int64(item.byteSize))),
            ("library.info.format", item.richFormatLabel),
            ("library.info.boards", boards.isEmpty ? nil : boards.joined(separator: ", ")),
        ]
        return rows.compactMap { key, value in value.map { (L10n.string(key), $0) } }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Owns the single Library window.
@MainActor
final class LibraryWindowController {
    let library = LibraryModel()
    private let window: NSWindow
    private let model: ClipboardViewModel
    private var keyMonitor: Any?

    init(model: ClipboardViewModel) {
        self.model = model
        let hosting = NSHostingController(rootView: LibraryView(model: model, library: library))
        window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = L10n.string("library.title")
        window.isReleasedWhenClosed = false
        // The title bar is part of the ground the cards lie on.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = AraPalette.nsGround
        window.contentMinSize = NSSize(width: LibraryView.minimumSize.width, height: LibraryView.minimumSize.height)
        window.setContentSize(NSSize(width: LibraryView.size.width, height: LibraryView.size.height))
        window.center()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            (self?.handleKey(event) ?? false) ? nil : event
        }
    }

    /// ⌫ deletes the selected clips and ⌘A selects all that are listed. The search field keeps
    /// the keyboard in this window, so the keys go to the list while the field is empty and to
    /// the field once something is typed in it.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === window, !event.isForInputMethod else { return false }
        if window.firstResponder is NSText, !library.searchText.isEmpty { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let items = library.visibleItems(of: model)
        switch (event.keyCode, flags) {
        case (51, []), (117, []):
            let selected = items.filter { library.selection.ids.contains($0.id) }
            guard !selected.isEmpty else { return false }
            selected.forEach { model.onDelete?($0) }
            return true
        case (0, .command):
            library.selection.selectAll(in: items.map(\.id))
            return true
        case (6, .command):
            // ⌘Z takes back the deletion made a moment ago.
            guard model.undoableDeletionCount > 0 else { return false }
            model.onUndoDelete?()
            return true
        case (49, []):
            // Space shows the chosen clip in full, as it does in Finder.
            guard let item = items.first(where: { library.selection.ids.contains($0.id) }) ?? items.first else { return false }
            model.onPreview?(item)
            return true
        default:
            return false
        }
    }

    /// Keeps the window out of screenshots and recordings, or lets it be captured again.
    func setHiddenFromCapture(_ isHidden: Bool) {
        window.sharingType = isHidden ? .none : .readOnly
    }

    func show() {
        // An accessory app is not frontmost by default, so activate before showing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
