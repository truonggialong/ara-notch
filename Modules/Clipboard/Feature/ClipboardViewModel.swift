import AppKit
import ClipboardCore
import Combine

/// State the clipboard page and the floating panel render from. Owned by `ClipboardController`.
@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    /// The order the whole history is listed in; boards keep their own order.
    @Published var sortOrder = ClipSortOrder.recentlyUsed
    var onSetSortOrder: ((ClipSortOrder) -> Void)?
    /// Which clip of the copy stack is pasted first.
    @Published var copyStackOrder = CopyStack.Order.firstCopiedFirst
    var onSetCopyStackOrder: ((CopyStack.Order) -> Void)?
    /// Searches the user saved, shown as chips beside the boards.
    @Published var savedFilters: [SavedFilter] = []
    /// Whether macOS reminders can be made from clips (the calendar feature is there to make them).
    @Published var canRemind = false
    /// What the on-device model can do right now, if anything.
    @Published var assistantActions: [String] = []
    @Published var searchText = ""
    /// Set when the history could not be opened; the page then shows an error instead of items.
    @Published var storeError: String?
    /// The highlighted clip, shared by the notch row and the panel list.
    @Published var selection = ClipSelection()
    /// True once the notch row is being driven by the keyboard, so it shows the selection.
    @Published var showsSelectionInNotch = false
    /// Bumped every time the panel is shown; the search field takes focus when it changes.
    @Published var panelFocusToken = 0
    /// A pinned panel stays open when it loses keyboard focus and after a paste or copy.
    @Published var isPanelPinned = false

    // MARK: Boards

    /// A board being created (`boardID` nil) or renamed.
    struct BoardDraft: Equatable {
        var boardID: Int64?
        var name: String
        var symbolName: String
        /// Localization key of the problem with the name, if any.
        var errorKey: String?
    }

    @Published var boards: [ClipBoard] = []
    /// The board whose clips are listed; nil lists the whole history.
    /// The clip that was just used from the page: it shows a tick for a moment.
    @Published var flashedItemID: Int64?
    @Published var selectedBoardID: Int64?
    @Published var boardItems: [ClipItem] = []
    /// Clip id → ids of the boards it is pinned to.
    @Published var membership: [Int64: Set<Int64>] = [:]
    @Published var boardDraft: BoardDraft?
    /// Bumped when the board editor opens, so its name field takes focus.
    @Published var boardEditorFocusToken = 0

    var onSelectBoard: ((Int64?) -> Void)?
    var onBeginNewBoard: (() -> Void)?
    var onEditBoard: ((ClipBoard) -> Void)?
    var onDeleteBoard: ((ClipBoard) -> Void)?
    var onCommitDraft: (() -> Void)?
    var onCancelDraft: (() -> Void)?
    var onTogglePin: ((ClipItem, ClipBoard) -> Void)?

    /// What the notch page and the floating panel list: the selected board's clips, or the
    /// whole history, narrowed by the search.
    var pageItems: [ClipItem] {
        Self.filter(selectedBoardID == nil ? sortOrder.sorted(items) : boardItems, by: searchText)
    }

    func isPinned(_ item: ClipItem) -> Bool {
        membership[item.id] != nil
    }

    func isPinned(_ item: ClipItem, to board: ClipBoard) -> Bool {
        membership[item.id]?.contains(board.id) ?? false
    }

    // MARK: Vault

    /// The passcode is being asked for, or chosen for the first time.
    /// A fingerprint can stand in for the passcode being asked for.
    @Published var canUseTouchID = false
    var onUnlockWithTouchID: (() -> Void)?

    struct PasscodePrompt: Equatable {
        enum Purpose: Equatable {
            /// Unlock the vault to show this locked board.
            case view(boardID: Int64)
            /// Unlock the vault, then lock this board.
            case lock(boardID: Int64)
            /// Unlock the vault, then remove this board's lock.
            case removeLock(boardID: Int64)
            /// Choose the passcode, then lock this board.
            case createAndLock(boardID: Int64)
        }

        var purpose: Purpose
        var passcode = ""
        var confirmation = ""
        /// Localization key of the problem with the entry, if any.
        var errorKey: String?

        var isCreating: Bool {
            if case .createAndLock = purpose { return true }
            return false
        }

        /// Says what was wrong and empties the entries, so the next try is typed afresh
        /// instead of after the digits that were refused.
        mutating func refuse(because errorKey: String) {
            self.errorKey = errorKey
            passcode = ""
            confirmation = ""
        }
    }

    @Published var vaultState: VaultState = .notSetUp
    @Published var passcodePrompt: PasscodePrompt?
    /// Bumped when the passcode row opens, so its field takes focus.
    @Published var passcodeFocusToken = 0

    var onSubmitPasscode: (() -> Void)?
    var onCancelPasscode: (() -> Void)?
    var onToggleBoardLock: ((ClipBoard) -> Void)?

    // MARK: Actions

    var onPaste: ((ClipItem) -> Void)?
    var onSaveFilter: (() -> Void)?
    var onRemoveFilter: ((SavedFilter) -> Void)?
    var onNewNote: (() -> Void)?
    var onRemind: ((ClipItem, ClipReminderPreset) -> Void)?
    /// Remind of the clip at a day and a time chosen by sight.
    var onRemindAt: ((ClipItem) -> Void)?
    /// Cut the subject of a picture out of its background, as a new clip.
    var onRemoveBackground: ((ClipItem) -> Void)?
    /// Save a picture clip to a file in the named format ("png", "jpeg", "heic").
    var onSaveImage: ((ClipItem, String) -> Void)?
    /// Run an on-device model action ("summarize", "rewrite") on a text clip.
    var onAssist: ((ClipItem, String) -> Void)?
    /// Paste without the clip's formatting.
    var onPastePlain: ((ClipItem) -> Void)?
    /// Open the window that edits the clip's title and text.
    var onEdit: ((ClipItem) -> Void)?
    /// Open a link in the browser, a file or an image in its default app.
    var onOpen: ((ClipItem) -> Void)?
    var onReveal: ((ClipItem) -> Void)?
    /// Open the clip's file in the app at this location.
    var onOpenWith: ((ClipItem, URL) -> Void)?
    /// The file an "Open With" menu is about, if the clip has one.
    var fileURL: ((ClipItem) -> URL?)?
    /// Copy the text read from an image clip.
    var onCopyRecognizedText: ((ClipItem) -> Void)?
    var onCopy: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?

    /// After a delete from a card's own button the next card slides under the pointer, its
    /// delete button already lit; a click that quick is a repeat, not a choice.
    static let quickDeletePause: TimeInterval = 0.6
    private var lastQuickDelete: Date?

    func quickDelete(_ item: ClipItem, at now: Date = Date()) {
        if let last = lastQuickDelete, now.timeIntervalSince(last) < Self.quickDeletePause { return }
        lastQuickDelete = now
        onDelete?(item)
    }
    /// How many clips the deletion that can still be undone took; 0 when there is none.
    @Published var undoableDeletionCount = 0
    var onUndoDelete: (() -> Void)?
    /// Show the clip in full in Quick Look, or put that view away.
    var onPreview: ((ClipItem) -> Void)?
    var onTransform: ((ClipItem, TextTransform) -> Void)?
    var onCopyColor: ((ClipItem, ClipColor.Format) -> Void)?
    /// Copy several things, then paste them one by one.
    @Published var copyStack = CopyStack()
    var onToggleCopyStack: (() -> Void)?
    /// Copy the text of several clips as one clip, a line each.
    var onCopyCombined: (([ClipItem]) -> Void)?
    /// PNG data of an image clip, for dragging it out.
    var imageData: ((ClipItem) -> Data?)?
    /// A clip, by id, was dropped on a board's chip.
    var onDropOnBoard: ((Int64, ClipBoard) -> Void)?
    /// A clip of the selected board was dropped on another of its clips: move it before that one.
    var onReorder: ((Int64, ClipItem) -> Void)?

    /// Text tools work on plain clips. A clip in the vault is left alone: the result would be
    /// stored outside the vault, unencrypted.
    static func canTransform(_ item: ClipItem) -> Bool {
        (item.kind == .text || item.kind == .link) && !item.isEncrypted
    }
    var thumbnail: ((ClipItem) -> NSImage?)?
    /// The larger copy of a picture, for the large preview.
    var previewImage: ((ClipItem) -> NSImage?)?
    /// The preview image of a link's page, when one was fetched.
    var linkImage: ((ClipItem) -> NSImage?)?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Keep the selection valid whenever the visible list changes.
        Publishers.CombineLatest4($items, $searchText, $selectedBoardID, $boardItems)
            .sink { [weak self] items, searchText, boardID, boardItems in
                let listed = Self.filter(boardID == nil ? items : boardItems, by: searchText)
                self?.selection.sync(with: listed.map(\.id))
            }
            .store(in: &cancellables)
    }

    var selectedItem: ClipItem? {
        guard let selectedID = selection.selectedID else { return nil }
        return pageItems.first { $0.id == selectedID }
    }

    /// Marks the clip as just used; the mark goes away by itself.
    func flash(_ item: ClipItem) {
        flashedItemID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            if self?.flashedItemID == item.id {
                self?.flashedItemID = nil
            }
        }
    }

    func select(_ item: ClipItem) {
        selection.select(id: item.id, in: pageItems.map(\.id))
    }

    /// Clears the search and puts the selection back on the first listed clip.
    func resetBrowsing() {
        searchText = ""
        selection = ClipSelection()
        selection.sync(with: pageItems.map(\.id))
    }

    private static func filter(_ items: [ClipItem], by searchText: String) -> [ClipItem] {
        let query = ClipQuery(searchText)
        return query.isEmpty ? items : items.filter(query.matches)
    }
}
