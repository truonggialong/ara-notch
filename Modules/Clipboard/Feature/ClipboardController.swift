import AppKit
import ClipboardCore
import Combine
import NotchShell
import os
import SwiftUI

/// Records what the user copies and serves the clipboard page of the notch.
@MainActor
public final class ClipboardController {
    /// Pause between handing focus back to the user's app and sending ⌘V to it.
    private static let pasteDelay: TimeInterval = 0.08

    private let settings: ClipboardSettings
    private let vaultKeychain: VaultKeychain
    private let notch: NotchController
    private let pasteboard: NSPasteboard
    private let viewModel = ClipboardViewModel()
    private let watcher: PasteboardWatcher
    /// Small copies of the pictures on show; at most this much memory, the oldest let go first.
    private let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private var pendingDeletions = PendingDeletions()
    private var deletionTimer: Timer?
    /// Quick Look is coming up: the panel is about to stop being the key window for that
    /// reason and must stay.
    private var isOpeningPreview = false
    private let settingsSectionState = ClipboardSettingsSectionState()
    private let keyRouter = KeyCommandRouter()
    private var panel: ClipboardPanel?
    private var libraryWindow: LibraryWindowController?
    private let pasteTap = PasteKeyTap()
    private let log = Logger(subsystem: "com.aranotch.app", category: "clipboard")
    private var store: ClipboardStore?
    /// Where a damaged history was put aside at launch, to be told once the notch is up.
    private var damagedHistory: URL?
    private var cancellables = Set<AnyCancellable>()

    /// When true the panel stays open after losing keyboard focus and after a paste or copy.
    public var isPanelPinned: Bool {
        get { viewModel.isPanelPinned }
        set { viewModel.isPanelPinned = newValue }
    }

    /// Lets link previews be fetched from this machine and the local network. For testing only:
    /// the policy refuses such hosts because opening them can trigger actions on local devices.
    public var allowsLocalLinkPreviews = false

    /// How often expired clips are looked for while the app runs.
    private static let retentionCheckInterval: TimeInterval = 3600
    private var retentionTimer: Timer?

    /// How long the vault stays unlocked after the passcode was entered.
    private static let vaultAutoLockInterval: TimeInterval = 300
    private var vaultLockTimer: Timer?

    /// Links whose preview is being fetched right now, so a quick second copy does not fetch twice.
    private var linkFetchesInFlight = Set<Int64>()

    public var isHotKeyRegistered: Bool {
        settings.hotKeyEnabled && notch.shortcuts.combos[.clipboardPanel] != nil
            && !notch.shortcuts.isRefused(.clipboardPanel)
    }

    public var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Window number of the floating panel while it exists; used to address test key events.
    public var panelWindowNumber: Int? {
        panel?.windowNumber
    }

    /// - Parameter pasteboard: the pasteboard to watch; anything but `.general` is for testing.
    public init(
        directory: URL,
        settings: ClipboardSettings,
        notch: NotchController,
        pasteboard: NSPasteboard = .general
    ) {
        self.settings = settings
        vaultKeychain = VaultKeychain(account: directory.path)
        self.notch = notch
        self.pasteboard = pasteboard
        watcher = PasteboardWatcher(pasteboard: pasteboard)

        do {
            let opened = try ClipboardStore.openRecovering(directory: directory, maxItems: settings.maxItems)
            store = opened.store
            damagedHistory = opened.setAside
            if let aside = opened.setAside {
                log.error("clipboard history was damaged; set aside as \(aside.lastPathComponent, privacy: .public)")
            }
        } catch {
            log.error("cannot open clipboard history: \(String(describing: error), privacy: .public)")
            viewModel.storeError = String(describing: error)
        }

        // Left out of Time Machine unless the user puts it back, now and whenever it is changed.
        settings.$excludedFromBackup
            .sink { [weak self] excluded in
                do {
                    try BackupExclusion.apply(excluded, to: directory)
                } catch {
                    self?.log.error("cannot mark the history for backups: \(String(describing: error), privacy: .public)")
                }
            }
            .store(in: &cancellables)

        viewModel.onPaste = { [weak self] item in self?.paste(item) }
        viewModel.onPastePlain = { [weak self] item in self?.paste(item, plain: true) }
        viewModel.onSaveFilter = { [weak self] in
            guard let self else { return }
            self.settings.savedFilters = SavedFilter.adding(self.viewModel.searchText, to: self.settings.savedFilters)
        }
        viewModel.onRemoveFilter = { [weak self] filter in
            guard let self else { return }
            self.settings.savedFilters = SavedFilter.removing(filter.query, from: self.settings.savedFilters)
        }
        viewModel.onRemind = { [weak self] item, preset in self?.remind(item, preset) }
        viewModel.onRemindAt = { [weak self] item in self?.remindAtChosenTime(item) }
        viewModel.onRemoveBackground = { [weak self] item in self?.removeBackground(of: item) }
        viewModel.onSaveImage = { [weak self] item, format in self?.saveImage(item, format: format) }
        viewModel.onAssist = { [weak self] item, action in self?.assist(item, action: action) }
        viewModel.onEdit = { [weak self] item in self?.edit(item) }
        viewModel.onOpen = { [weak self] item in self?.open(item) }
        viewModel.onReveal = { item in
            NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) })
        }
        viewModel.onOpenWith = { [weak self] item, app in self?.open(item, with: app) }
        viewModel.fileURL = { [weak self] item in self?.fileURL(of: item) }
        viewModel.onCopyRecognizedText = { [weak self] item in
            guard let self, let text = item.recognizedText, !text.isEmpty else { return }
            _ = self.derive(text, from: item)
        }
        viewModel.onCopy = { [weak self] item in self?.copy(item) }
        viewModel.onDelete = { [weak self] item in self?.delete(item) }
        viewModel.onSetSortOrder = { [weak self] order in self?.settings.sortOrder = order }
        viewModel.onSetCopyStackOrder = { [weak self] order in
            self?.settings.copyStackOrder = order
            self?.viewModel.copyStack.order = order
        }
        viewModel.onUndoDelete = { [weak self] in self?.undoDelete() }
        viewModel.onPreview = { [weak self] item in self?.preview(item) }
        viewModel.onTransform = { [weak self] item, tool in self?.transform(item, with: tool) }
        viewModel.onCopyColor = { [weak self] item, format in self?.copyColor(of: item, as: format) }
        viewModel.onCopyCombined = { [weak self] items in self?.copyCombined(items) }
        viewModel.onToggleCopyStack = { [weak self] in self?.toggleCopyStack() }
        pasteTap.onPaste = { [weak self] in self?.userIsPasting() }
        viewModel.imageData = { [weak self] item in self?.store?.imageData(for: item) }
        viewModel.onDropOnBoard = { [weak self] itemID, board in self?.pinDropped(itemID: itemID, on: board) }
        viewModel.onReorder = { [weak self] itemID, target in self?.moveDropped(itemID: itemID, before: target) }
        viewModel.thumbnail = { [weak self] item in self?.thumbnail(for: item) }
        viewModel.previewImage = { [weak self] item in self?.thumbnail(for: item, maxPixelSize: ClipThumbnail.maxPixelSize) }
        viewModel.linkImage = { [weak self] item in self?.linkImage(for: item) }
        viewModel.onSelectBoard = { [weak self] id in self?.selectBoard(id: id) }
        viewModel.onBeginNewBoard = { [weak self] in self?.beginNewBoard() }
        viewModel.onEditBoard = { [weak self] board in self?.beginEditing(board) }
        viewModel.onDeleteBoard = { [weak self] board in self?.perform { try $0.deleteBoard(id: board.id) } }
        viewModel.onCommitDraft = { [weak self] in self?.commitBoardDraft() }
        viewModel.onCancelDraft = { [weak self] in self?.viewModel.boardDraft = nil }
        viewModel.onTogglePin = { [weak self] item, board in self?.togglePin(item, board) }
        viewModel.onToggleBoardLock = { [weak self] board in self?.toggleLock(of: board) }
        viewModel.onSubmitPasscode = { [weak self] in self?.submitPasscode() }
        viewModel.onUnlockWithTouchID = { [weak self] in self?.unlockWithTouchID() }
        // Turning the fingerprint off takes the kept passcode out of the keychain.
        settings.$vaultTouchID
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.vaultKeychain.delete()
                self?.viewModel.canUseTouchID = false
            }
            .store(in: &cancellables)
        viewModel.onCancelPasscode = { [weak self] in self?.viewModel.passcodePrompt = nil }
        reload()
    }

    /// Starts recording pasteboard changes. Does nothing when the history could not be opened.
    public func start() {
        guard store != nil else { return }
        watcher.onChange = { [weak self] in self?.pasteboardChanged() ?? true }
        watcher.start()
        if damagedHistory != nil {
            announceDamagedHistory()
        }

        settings.$maxItems
            .dropFirst()
            .sink { [weak self] maxItems in self?.perform { try $0.setMaxItems(maxItems) } }
            .store(in: &cancellables)
        // Same reason as in `showPanel`: catch a fresh copy before the notch can take focus.
        notch.isOpenPublisher
            .filter { $0 }
            .sink { [weak self] _ in self?.watcher.pollNow() }
            .store(in: &cancellables)
        notch.isOpenPublisher
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.viewModel.searchText = ""
                self?.viewModel.showsSelectionInNotch = false
                self?.viewModel.boardDraft = nil
                self?.viewModel.passcodePrompt = nil
            }
            .store(in: &cancellables)

        // The panel and the Library show clipboard content, so they follow the same switch as the notch.
        notch.settings.$hidesFromCapture
            .sink { [weak self] hides in
                self?.panel?.sharingType = hides ? .none : .readOnly
                self?.libraryWindow?.setHiddenFromCapture(hides)
            }
            .store(in: &cancellables)
        settings.$bareHexColors
            .sink { [weak self] isOn in self?.store?.recognisesBareHexColors = isOn }
            .store(in: &cancellables)
        // Expired clips are removed at launch, whenever the setting changes, and hourly.
        settings.$retention
            .sink { [weak self] retention in self?.applyRetention(retention) }
            .store(in: &cancellables)
        let retentionTimer = Timer(timeInterval: Self.retentionCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyRetention(self.settings.retention)
            }
        }
        retentionTimer.tolerance = 60
        RunLoop.main.add(retentionTimer, forMode: .common)
        self.retentionTimer = retentionTimer

        settings.$sortOrder
            .sink { [weak self] order in self?.viewModel.sortOrder = order }
            .store(in: &cancellables)
        settings.$copyStackOrder
            .sink { [weak self] order in self?.viewModel.copyStackOrder = order }
            .store(in: &cancellables)
        settings.$savedFilters
            .sink { [weak self] filters in self?.viewModel.savedFilters = filters }
            .store(in: &cancellables)
        settings.$readsTextInImages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readTextInImagesIfNeeded() }
            .store(in: &cancellables)
        notch.shortcuts.setHandler(.clipboardPanel) { [weak self] in self?.togglePanel() }
        notch.shortcuts.setNumberRow(ClipboardNumberRows.pinned) { [weak self] number in self?.quickPaste(number: number) }
        notch.shortcuts.setNumberRow(ClipboardNumberRows.recent) { [weak self] number in self?.pasteRecent(number: number) }
        schedulePauseEnd()
        settings.$hotKeyEnabled
            .sink { [weak self] isEnabled in self?.notch.shortcuts.setEnabled(isEnabled, for: .clipboardPanel) }
            .store(in: &cancellables)
        keyRouter.start { [weak self] event in self?.handleKey(event) ?? false }
        // Pictures copied before this was possible, or while it was off, are read now.
        readTextInImagesIfNeeded()
    }

    /// The latest clips, as a tile of the overview page.
    public func makeOverviewTile() -> AnyView {
        AnyView(ClipboardWidget(model: viewModel) { [weak notch] in notch?.selectPage(id: "clipboard") })
    }



    public func makePage() -> NotchPage {
        var page = NotchPage(
            id: "clipboard", titleKey: "page.clipboard.title", symbolName: "doc.on.clipboard", hue: .peach
        ) { [viewModel] in
            ClipboardPageView(model: viewModel)
        }
        // The row of clips and the row of chips both run sideways.
        page.wheelScrollsSideways = true
        return page
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(ClipboardSettingsSection(
            settings: settings, state: settingsSectionState, shortcuts: notch.shortcuts, model: viewModel,
            onPause: { [weak self] pause in self?.pause(pause) },
            onResume: { [weak self] in self?.resume() }))
    }

    /// The floating panel and a new note, for Settings › Tools and shortcuts.
    public func makeToolSettings() -> AnyView {
        AnyView(ClipboardToolSettings(settings: settings, shortcuts: notch.shortcuts))
    }

    /// Link previews, text in pictures, backups and clearing, for Settings › Clipboard.
    public func makeDataSettings() -> AnyView {
        let state = settingsSectionState
        return AnyView(ClipboardDataSettings(
            settings: settings, state: state,
            onClearRange: { [weak self] range in self?.clear(range) },
            onClearHistory: { [weak self] in
                self?.thumbnails.removeAllObjects()
                self?.perform { try $0.deleteAll() }
            },
            onExportBackup: { [weak self] in
                BackupPanels.export(reportingTo: state) { url in
                    guard let self else { throw ClipboardStoreError.cannotOpen("") }
                    return try self.exportBackup(to: url)
                }
            },
            onRestoreBackup: { [weak self] in
                BackupPanels.restore(reportingTo: state) { url in
                    guard let self else { throw ClipboardStoreError.cannotOpen("") }
                    return try self.restoreBackup(from: url)
                }
            }))
    }

    /// Letting AI agents read the history, for Settings › Agents.
    public func makeAgentAccessSettings() -> AnyView {
        AnyView(ClipboardAgentAccessSettings(settings: settings))
    }

    // MARK: - Library

    /// Shows the Library window.
    /// - Parameters:
    ///   - filter: what to list: `kind:<kind>`, `app:<name>` or `board:<name>`; nil keeps the current filter.
    ///   - layout: `grid` or `list`; nil keeps the current layout.
    public func showLibrary(filter: String? = nil, layout: String? = nil) {
        let controller = libraryWindow ?? LibraryWindowController(model: viewModel)
        libraryWindow = controller
        controller.setHiddenFromCapture(notch.settings.hidesFromCapture)
        if let filter, let parsed = libraryFilter(named: filter) {
            controller.library.filter = parsed
        }
        if let layout = layout.flatMap(LibraryModel.Layout.init(rawValue:)) {
            controller.library.layout = layout
        }
        controller.show()
    }

    private func libraryFilter(named name: String) -> LibraryFilter? {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "kind": return ClipKind(rawValue: parts[1]).map(LibraryFilter.kind)
        case "app": return .app(parts[1])
        case "board": return viewModel.boards.first { $0.name == parts[1] }.map { .board($0.id) }
        default: return nil
        }
    }

    // MARK: - Backup

    /// Writes the history and the unlocked boards to a backup file. Vault clips are left out.
    /// - Returns: how many locked boards were left out.
    @discardableResult
    public func exportBackup(to url: URL) throws -> Int {
        guard let store else { throw ClipboardStoreError.cannotOpen(viewModel.storeError ?? "") }
        try store.makeBackup(at: Date()).encoded().write(to: url, options: .atomic)
        return try store.boards().filter(\.isLocked).count
    }

    /// Merges a backup file into the history and the boards.
    @discardableResult
    public func restoreBackup(from url: URL) throws -> ClipBackupSummary {
        guard let store else { throw ClipboardStoreError.cannotOpen(viewModel.storeError ?? "") }
        let backup = try ClipBackup.decode(try Data(contentsOf: url))
        defer { reload() }
        return try store.restore(backup, at: Date())
    }

    /// Adds content to the history directly, bypassing the pasteboard and the privacy rules.
    /// Never triggers a link preview fetch; only real pasteboard copies do.
    public func capture(_ content: ClipContent, rich: ClipRichData? = nil, source: ClipSource) {
        add(content, rich: rich, source: source)
    }

    @discardableResult
    private func add(_ content: ClipContent, rich: ClipRichData?, source: ClipSource, at date: Date = Date()) -> ClipItem? {
        var added: ClipItem?
        perform { added = try $0.add(content, rich: rich, source: source, at: date) }
        return added
    }

    public func setSearchText(_ text: String) {
        viewModel.searchText = text
    }

    // MARK: - Boards

    /// Ids of the whole history, newest first.
    public var newestItemIDs: [Int64] {
        viewModel.items.map(\.id)
    }

    /// Applies the text tool with this name to the newest text clip, as the menu would.
    @discardableResult
    public func transformNewestText(withToolNamed name: String) -> Bool {
        guard let tool = TextTransform(rawValue: name),
              let item = viewModel.items.first(where: { $0.kind == .text })
        else { return false }
        return transform(item, with: tool)
    }

    /// Copies the newest colour clip in this notation (`hex`, `rgb`, `hsl`), as the menu would.
    @discardableResult
    public func copyNewestColor(asFormatNamed name: String) -> Bool {
        guard let format = ClipColor.Format(rawValue: name),
              let item = viewModel.items.first(where: { $0.kind == .color })
        else { return false }
        return copyColor(of: item, as: format)
    }

    /// Creates a board. Returns false when the name is not acceptable or the limit is reached.
    @discardableResult
    public func createBoard(name: String, symbolName: String) -> Bool {
        guard let store else { return false }
        do {
            try store.createBoard(name: name, symbolName: symbolName, at: Date())
            reload()
            return true
        } catch {
            return false
        }
    }

    public func pin(itemID: Int64, toBoardNamed name: String) {
        guard let board = viewModel.boards.first(where: { $0.name == name }) else { return }
        perform { try $0.pin(itemID: itemID, toBoard: board.id, at: Date()) }
    }

    /// Shows the named board on the notch page; nil or an unknown name shows the whole history.
    public func selectBoard(named name: String?) {
        selectBoard(id: viewModel.boards.first { $0.name == name }?.id)
    }

    /// Opens the editor for a new board in place of the search row.
    public func beginNewBoard() {
        // A name is there already, so a board can be made without typing; typing replaces it.
        let name = BoardNames.suggested(
            base: L10n.string("clipboard.boards.defaultName"), existing: viewModel.boards.map(\.name))
        viewModel.boardDraft = ClipboardViewModel.BoardDraft(
            boardID: nil, name: name, symbolName: BoardSymbols.fallback, errorKey: nil)
        viewModel.boardEditorFocusToken += 1
    }

    private func beginEditing(_ board: ClipBoard) {
        viewModel.boardDraft = ClipboardViewModel.BoardDraft(
            boardID: board.id, name: board.name, symbolName: board.symbolName, errorKey: nil)
        viewModel.boardEditorFocusToken += 1
    }

    private func selectBoard(id: Int64?) {
        if let board = viewModel.boards.first(where: { $0.id == id }), board.isLocked,
           viewModel.vaultState != .unlocked {
            askForPasscode(.view(boardID: board.id))
            return
        }
        viewModel.selectedBoardID = id
        reload()
    }

    // MARK: - Vault

    /// Creates the vault and locks the named board, then locks the vault. For automated checks.
    public func seedVault(passcode: String, lockingBoardNamed name: String) {
        guard let store, let board = viewModel.boards.first(where: { $0.name == name }) else { return }
        do {
            try store.createVault(passcode: passcode)
            try store.setBoardLocked(id: board.id, true)
        } catch {
            log.error("cannot seed vault: \(String(describing: error), privacy: .public)")
        }
        lockVault()
    }

    /// Unlocks the vault with the passcode. Returns false when it is wrong. For automated checks.
    @discardableResult
    public func unlockVault(passcode: String) -> Bool {
        guard let store, (try? store.unlockVault(passcode: passcode)) != nil else { return false }
        vaultUnlocked()
        reload()
        return true
    }

    private func toggleLock(of board: ClipBoard) {
        switch (board.isLocked, viewModel.vaultState) {
        case (_, .unlocked):
            perform { try $0.setBoardLocked(id: board.id, !board.isLocked) }
        case (false, .notSetUp):
            askForPasscode(.createAndLock(boardID: board.id))
        case (false, .locked):
            askForPasscode(.lock(boardID: board.id))
        case (true, _):
            askForPasscode(.removeLock(boardID: board.id))
        }
    }

    private func askForPasscode(_ purpose: ClipboardViewModel.PasscodePrompt.Purpose) {
        viewModel.boardDraft = nil
        let prompt = ClipboardViewModel.PasscodePrompt(purpose: purpose)
        viewModel.canUseTouchID = VaultTouchID.shouldOffer(
            isEnabled: settings.vaultTouchID, hasSavedPasscode: vaultKeychain.hasPasscode,
            canUseBiometrics: VaultFingerprint.isAvailable, isCreating: prompt.isCreating)
        viewModel.passcodePrompt = prompt
        viewModel.passcodeFocusToken += 1
    }

    private func submitPasscode() {
        guard let store, let prompt = viewModel.passcodePrompt else { return }
        do {
            if prompt.isCreating {
                guard prompt.passcode == prompt.confirmation else {
                    viewModel.passcodePrompt?.refuse(because: "clipboard.vault.error.mismatch")
                    return
                }
                try store.createVault(passcode: prompt.passcode)
            } else {
                try store.unlockVault(passcode: prompt.passcode)
            }
            vaultUnlocked()
            // Kept for the fingerprint only while the user wants that.
            if settings.vaultTouchID {
                vaultKeychain.save(prompt.passcode)
            }

            switch prompt.purpose {
            case .view(let boardID):
                viewModel.selectedBoardID = boardID
            case .lock(let boardID), .createAndLock(let boardID):
                try store.setBoardLocked(id: boardID, true)
            case .removeLock(let boardID):
                try store.setBoardLocked(id: boardID, false)
            }
            viewModel.passcodePrompt = nil
            reload()
        } catch ClipboardStoreError.wrongPasscode {
            viewModel.passcodePrompt?.refuse(because: "clipboard.vault.error.wrong")
            // A kept passcode that no longer opens the vault is of no use to the fingerprint.
            if vaultKeychain.read() == prompt.passcode {
                vaultKeychain.delete()
                viewModel.canUseTouchID = false
            }
        } catch ClipboardStoreError.invalidPasscode {
            viewModel.passcodePrompt?.refuse(because: "clipboard.vault.error.short")
        } catch {
            log.error("vault operation failed: \(String(describing: error), privacy: .public)")
            viewModel.passcodePrompt = nil
            reload()
        }
    }

    /// Asks for a fingerprint and, when it is the user's, unlocks with the kept passcode.
    private func unlockWithTouchID() {
        guard let asked = viewModel.passcodePrompt else { return }
        // The system's own dialog draws the pointer away from the notch, which would close
        // and forget what the passcode was asked for: the notch is held open, and the
        // question is put back if it went all the same.
        notch.open()
        VaultFingerprint.ask(reason: L10n.string("clipboard.vault.touchID.reason")) { [weak self] isOwner in
            guard let self, isOwner, let passcode = self.vaultKeychain.read() else { return }
            var prompt = self.viewModel.passcodePrompt ?? asked
            prompt.passcode = passcode
            self.viewModel.passcodePrompt = prompt
            self.submitPasscode()
        }
    }

    /// Starts the countdown after which the vault locks itself again.
    private func vaultUnlocked() {
        vaultLockTimer?.invalidate()
        let timer = Timer(timeInterval: Self.vaultAutoLockInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockVault() }
        }
        RunLoop.main.add(timer, forMode: .common)
        vaultLockTimer = timer
    }

    private func lockVault() {
        vaultLockTimer?.invalidate()
        vaultLockTimer = nil
        store?.lockVault()
        // Decrypted pictures and text must not outlive the unlocked vault in the caches.
        thumbnails.removeAllObjects()
        CodeHighlighter.clearCache()
        reload()
    }

    private func commitBoardDraft() {
        guard let store, let draft = viewModel.boardDraft else { return }
        do {
            if let boardID = draft.boardID {
                try store.updateBoard(id: boardID, name: draft.name, symbolName: draft.symbolName)
            } else {
                let board = try store.createBoard(name: draft.name, symbolName: draft.symbolName, at: Date())
                viewModel.selectedBoardID = board.id
            }
            viewModel.boardDraft = nil
            reload()
        } catch ClipboardStoreError.invalidBoardName {
            viewModel.boardDraft?.errorKey = "clipboard.boards.error.invalid"
        } catch ClipboardStoreError.duplicateBoardName {
            viewModel.boardDraft?.errorKey = "clipboard.boards.error.duplicate"
        } catch ClipboardStoreError.tooManyBoards {
            viewModel.boardDraft?.errorKey = "clipboard.boards.error.limit"
        } catch {
            log.error("cannot save board: \(String(describing: error), privacy: .public)")
            viewModel.boardDraft = nil
        }
    }

    private func togglePin(_ item: ClipItem, _ board: ClipBoard) {
        AraHaptics.play(.tap)
        if board.isLocked, viewModel.vaultState != .unlocked {
            askForPasscode(.view(boardID: board.id))
            return
        }
        if viewModel.isPinned(item, to: board) {
            perform { try $0.unpin(itemID: item.id, fromBoard: board.id) }
        } else {
            perform { try $0.pin(itemID: item.id, toBoard: board.id, at: Date()) }
        }
    }

    /// A clip dragged onto a board's chip is pinned there; dropping it again changes nothing.
    private func pinDropped(itemID: Int64, on board: ClipBoard) {
        AraHaptics.play(.tap)
        if board.isLocked, viewModel.vaultState != .unlocked {
            askForPasscode(.view(boardID: board.id))
            return
        }
        perform { try $0.pin(itemID: itemID, toBoard: board.id, at: Date()) }
    }

    /// Reorders the selected board: the dragged clip goes before the one it was dropped on.
    private func moveDropped(itemID: Int64, before target: ClipItem) {
        guard let boardID = viewModel.selectedBoardID else { return }
        perform { try $0.moveItem(itemID, inBoard: boardID, before: target.id, at: Date()) }
    }

    /// Pins a clip to a board as a drop on its chip would, and optionally moves it before
    /// another clip of that board, as a drop on that clip would.
    public func dropItem(itemID: Int64, onBoardNamed name: String, before otherID: Int64? = nil) {
        guard let board = viewModel.boards.first(where: { $0.name == name }) else { return }
        pinDropped(itemID: itemID, on: board)
        if let otherID {
            perform { try $0.moveItem(itemID, inBoard: board.id, before: otherID, at: Date()) }
        }
    }

    // MARK: - Panel

    public func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Shows the floating panel next to the pointer and gives it keyboard focus.
    public func showPanel() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            return
        }
        // Record anything copied a moment ago before this panel takes keyboard focus; once it
        // has focus, pasteboard changes are taken to come from the app's own fields.
        watcher.pollNow()
        let panel = self.panel ?? makePanel()
        viewModel.resetBrowsing()
        viewModel.panelFocusToken += 1
        panel.setFrame(
            PanelPlacement.frame(size: ClipboardPanelView.size, near: pointer, in: screen.visibleFrame),
            display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(contentView: NSHostingView(rootView: ClipboardPanelView(model: viewModel)))
        panel.onResignKey = { [weak self] in
            // Deferred: resigning key can happen in the middle of this panel's own event handling.
            DispatchQueue.main.async {
                guard let self, !self.isPanelPinned, !self.isOpeningPreview, !AraQuickLook.shared.isShowing else { return }
                self.hidePanel()
            }
        }
        panel.sharingType = notch.settings.hidesFromCapture ? .none : .readOnly
        self.panel = panel
        return panel
    }

    // MARK: - Keyboard

    /// Handles a key press in the panel or in the notch's clipboard page.
    /// Returns true when the key was a list command and must not reach the search field.
    public func handleKey(_ event: NSEvent) -> Bool {
        let axis: ClipListAxis
        if let panel, event.window === panel {
            axis = .vertical
        } else if notch.owns(event.window), notch.isKeyWindow, notch.selectedPageID == "clipboard" {
            axis = .horizontal
        } else {
            return false
        }

        // While the passcode is being entered, the keys belong to its fields.
        if viewModel.passcodePrompt != nil {
            switch event.keyCode {
            case 36, 76:
                submitPasscode()
                return true
            case 53:
                viewModel.passcodePrompt = nil
                return true
            default:
                return false
            }
        }

        // While a board is being named, the keys belong to its name field.
        if axis == .horizontal, viewModel.boardDraft != nil {
            switch event.keyCode {
            case 36, 76:
                commitBoardDraft()
                return true
            case 53:
                viewModel.boardDraft = nil
                return true
            default:
                return false
            }
        }

        let list = viewModel.pageItems
        let selected = viewModel.selectedItem

        let command = ClipPanelKeyMap.command(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            axis: axis,
            searchIsEmpty: viewModel.searchText.isEmpty)

        switch command {
        case .passThrough:
            return false
        case .moveNext:
            moveSelection(axis: axis, in: list) { $0.moveNext(in: $1) }
        case .movePrevious:
            moveSelection(axis: axis, in: list) { $0.movePrevious(in: $1) }
        case .paste:
            selected.map { paste($0) }
        case .pastePlain:
            selected.map { paste($0, plain: true) }
        case .copy:
            if let selected, copy(selected) {
                dismissAfterUse()
            }
        case .delete:
            selected.map(delete)
        case .pasteIndex(let index):
            if list.indices.contains(index) {
                paste(list[index])
            }
        case .clearSearch:
            viewModel.searchText = ""
        case .close:
            dismiss()
        case .undo:
            // With nothing to take back, the key is the search field's own undo.
            guard viewModel.undoableDeletionCount > 0 else { return false }
            undoDelete()
        case .preview:
            guard let selected else { return false }
            preview(selected)
        }
        return true
    }

    private func moveSelection(
        axis: ClipListAxis, in list: [ClipItem], _ move: (inout ClipSelection, [Int64]) -> Void
    ) {
        if axis == .horizontal {
            viewModel.showsSelectionInNotch = true
        }
        move(&viewModel.selection, list.map(\.id))
    }

    /// Closes whichever clipboard surface is open; this also returns keyboard focus to the user's app.
    private func dismiss() {
        hidePanel()
        notch.close()
    }

    /// After a clip was pasted or copied: a pinned panel stays on screen but gives keyboard
    /// focus back to the user's app, so the paste lands there; anything else closes.
    private func dismissAfterUse() {
        guard isPanelPinned, let panel, panel.isVisible else {
            dismiss()
            return
        }
        notch.close()
        // Taking the panel off screen and putting it back is how it stops being the key window.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Recording

    /// Returns false when the pasteboard held nothing readable yet, so the watcher retries.
    private func pasteboardChanged() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = ClipSource(bundleID: frontmost?.bundleIdentifier, appName: frontmost?.localizedName)

        // Check the type markers first, so private content is never even read.
        guard ClipboardPrivacy.shouldCapture(
            pasteboardTypes: PasteboardReader.types(of: pasteboard),
            source: source,
            isPaused: settings.isPausedNow,
            ignoredBundleIDs: Set(settings.ignoredBundleIDs),
            // One of this app's windows holding keyboard focus means the copy happened in it.
            isFromOwnInterface: NSApp.keyWindow != nil)
        else { return true }
        guard let content = PasteboardReader.read(pasteboard) else { return false }
        // A copy that is a secret in itself is left out, and the user is told why nothing was kept.
        if settings.skipsSensitiveText, case .text(let text) = content, let reason = SensitiveText.reason(for: text) {
            announceSkipped(reason)
            return true
        }
        // A picture is turned into what is kept away from the main thread: a large photo takes
        // a good part of a second, which would freeze the notch. It is dated by the copy.
        if case .image(let raw) = content {
            let copiedAt = Date()
            Task.detached(priority: .userInitiated) { [weak self] in
                let stored = ClipImageData.stored(from: raw)
                await self?.record(stored.map(ClipContent.image), rich: nil, source: source, at: copiedAt)
            }
            return true
        }
        var rich: ClipRichData?
        if case .text = content {
            rich = PasteboardReader.readRich(pasteboard)
        }
        record(content, rich: rich, source: source, at: Date())
        return true
    }

    private func record(_ content: ClipContent?, rich: ClipRichData?, source: ClipSource, at date: Date) {
        guard let content else { return }
        if ClipboardStore.isTooLarge(content) {
            announceNotSaved(L10n.string("clipboard.skipped.tooLarge"), symbol: "externaldrive.badge.exclamationmark")
            return
        }
        guard let item = add(content, rich: rich, source: source, at: date) else { return }
        fetchLinkPreviewIfNeeded(for: item)
        readTextInImagesIfNeeded()
        if viewModel.copyStack.isActive {
            viewModel.copyStack.push(item.id)
            announceCopyStack()
        } else {
            confirmCopy()
        }
    }

    // MARK: - Copy stack

    /// Whether the copy stack is collecting.
    public var isCopyStackActive: Bool {
        viewModel.copyStack.isActive
    }

    /// Starts or stops the copy stack. Starting needs Accessibility permission, because the
    /// app has to notice each ⌘V; returns false, with a beep, when it is missing.
    @discardableResult
    public func toggleCopyStack() -> Bool {
        if viewModel.copyStack.isActive {
            stopCopyStack()
            return true
        }
        guard pasteTap.start() else {
            NSSound.beep()
            Paster.requestTrust()
            return false
        }
        viewModel.copyStack.order = settings.copyStackOrder
        viewModel.copyStack.start()
        announceCopyStack()
        return true
    }

    private func stopCopyStack() {
        viewModel.copyStack.stop()
        pasteTap.stop()
        notch.dismissActivity(id: Self.copyStackActivityID)
    }

    /// Runs just before a ⌘V reaches the app in front: the next stacked clip goes on the
    /// pasteboard, so that is what gets pasted.
    private func userIsPasting() {
        guard let id = viewModel.copyStack.next() else { return }
        if let store, let item = try? store.item(id: id),
           PasteboardWriter.write(item, imageData: store.imageData(for: item), rich: store.richData(for: item), to: pasteboard) {
            watcher.ignoreCurrentContents()
        }
        if viewModel.copyStack.isActive {
            announceCopyStack()
        } else {
            stopCopyStack()
        }
    }

    private static let copyStackActivityID = "clipboard.copyStack"

    /// Shows how many clips are waiting in the stack.
    private func announceCopyStack() {
        let count = viewModel.copyStack.count
        notch.present(NotchLiveActivity(
            id: Self.copyStackActivityID, priority: 2, duration: 2.5, pageID: "clipboard",
            sign: AraSign(
                icon: .symbol("square.stack.3d.up.fill"), mark: "Clipboard",
                rows: [AraSign.Row(L10n.string("sign.clipboard.stack"), badge: .digits(String(count)))])))
    }

    // MARK: - Retention and feedback

    private func applyRetention(_ retention: ClipRetention) {
        guard let cutoff = retention.cutoff(from: Date()) else { return }
        perform { try $0.deleteUnpinned(olderThan: cutoff) }
    }

    /// The history could not be read and a new one was started: said once, at launch, so the
    /// empty clipboard page is not a mystery.
    private func announceDamagedHistory() {
        notch.present(NotchLiveActivity(
            id: "clipboard.damaged", priority: 2, duration: 8, pageID: "clipboard",
            sign: AraSign(
                tone: .danger, icon: .symbol("exclamationmark.triangle.fill"), mark: "Clipboard",
                title: L10n.string("clipboard.damaged.title"),
                rows: [AraSign.Row(
                    L10n.string("clipboard.damaged.row"), detail: L10n.string("clipboard.damaged.detail"))])))
    }

    private func announceSkipped(_ reason: SensitiveText.Reason) {
        announceNotSaved(L10n.string("clipboard.skipped.\(reason.rawValue)"), symbol: "lock.fill")
    }

    private func announceNotSaved(_ message: String, symbol: String) {
        notch.present(NotchLiveActivity(
            id: "clipboard.skipped", priority: 1, duration: 2.5, pageID: "clipboard",
            sign: AraSign(
                tone: .attention, icon: .symbol(symbol), mark: "Clipboard",
                rows: [AraSign.Row(message, detail: L10n.string("sign.clipboard.notSaved"))])))
    }

    // MARK: - Pausing and clearing

    private var pauseTimer: Timer?

    /// Stops recording for a while, or until it is turned back on.
    public func pause(_ pause: CapturePause) {
        if let end = pause.end(from: Date(), calendar: .current) {
            settings.isPaused = false
            settings.pausedUntil = end
        } else {
            settings.pausedUntil = nil
            settings.isPaused = true
        }
        schedulePauseEnd()
    }

    /// Whether copies are being recorded right now.
    public var recordingState: RecordingState {
        RecordingState(isPaused: settings.isPaused, pausedUntil: settings.pausedUntil, now: Date())
    }

    public func resume() {
        settings.isPaused = false
        settings.pausedUntil = nil
        schedulePauseEnd()
    }

    /// Clears the remembered end of a timed pause when it is reached, so the settings show
    /// recording as on again.
    private func schedulePauseEnd() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        guard let end = settings.pausedUntil else { return }
        guard end > Date() else {
            settings.pausedUntil = nil
            return
        }
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settings.pausedUntil = nil }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    /// Deletes a part of the history: what was copied in the last while, or what is older than
    /// a while. Pinned clips stay.
    public func clear(_ range: ClearRange) {
        let cutoff = range.cutoff(from: Date())
        thumbnails.removeAllObjects()
        if range.clearsRecent {
            perform { try $0.deleteUnpinned(usedSince: cutoff) }
        } else {
            perform { try $0.deleteUnpinned(olderThan: cutoff) }
        }
    }

    /// Pastes the Nth most recent clip into the app in front.
    private func pasteRecent(number: Int) {
        let items = viewModel.items
        guard items.indices.contains(number - 1), copy(items[number - 1]) else {
            NSSound.beep()
            return
        }
        playFeedbackSound()
        guard Paster.isTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Paster.pasteIntoFrontmostApp()
        }
    }

    /// A soft sound and a brief notice beside the notch tell the user the copy was recorded,
    /// each when it is on.
    private func confirmCopy() {
        playFeedbackSound()
        guard settings.copySign else { return }
        notch.present(NotchLiveActivity(
            id: "clipboard.copied", priority: 1, duration: 1.2, pageID: "clipboard",
            sign: AraSign(
                icon: .symbol("doc.on.clipboard.fill"), mark: "Clipboard",
                rows: [AraSign.Row(L10n.string("clipboard.copied"))])))
    }

    // MARK: - Link previews

    /// Fetches the page of a freshly copied link once, if the setting and the safety policy allow.
    private func fetchLinkPreviewIfNeeded(for item: ClipItem) {
        guard item.kind == .link, item.linkCheckedAt == nil, settings.linkPreviews,
              !linkFetchesInFlight.contains(item.id),
              let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)),
              LinkPreviewPolicy.shouldFetch(url, allowLocalHosts: allowsLocalLinkPreviews)
        else { return }

        let fetcher = LinkPreviewFetcher(allowLocalHosts: allowsLocalLinkPreviews)
        let id = item.id
        linkFetchesInFlight.insert(id)
        Task { [weak self] in
            let result = await fetcher.fetch(url)
            guard let self else { return }
            self.linkFetchesInFlight.remove(id)
            self.perform {
                try $0.setLinkPreview(id: id, title: result.title, imageData: result.imageData, at: Date())
            }
        }
    }

    private func linkImage(for item: ClipItem) -> NSImage? {
        guard let blobName = item.linkImageBlobName else { return nil }
        if let cached = thumbnails.object(forKey: blobName as NSString) { return cached }
        guard let data = store?.linkImageData(for: item) else { return nil }
        return cachedThumbnail(of: data, key: blobName)
    }

    // MARK: - Actions

    /// - Parameter plain: put only the text on the pasteboard, without its formatting.
    private func paste(_ item: ClipItem, plain: Bool = false) {
        AraHaptics.play(.tap)
        guard copy(item, plain: plain) else { return }
        dismissAfterUse()
        playFeedbackSound()
        guard settings.pasteOnClick, Paster.isTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Paster.pasteIntoFrontmostApp()
        }
    }

    @discardableResult
    private func copy(_ item: ClipItem, plain: Bool = false) -> Bool {
        guard let store,
              PasteboardWriter.write(
                  item, imageData: store.imageData(for: item), rich: plain ? nil : store.richData(for: item),
                  to: pasteboard)
        else { return false }
        watcher.ignoreCurrentContents()
        perform { try $0.touch(id: item.id, at: Date()) }
        return true
    }

    /// Rewrites a text clip with a tool. Returns false, with a beep, when the tool cannot work
    /// on this clip.
    @discardableResult
    private func transform(_ item: ClipItem, with tool: TextTransform) -> Bool {
        derive(ClipboardViewModel.canTransform(item) ? tool.apply(to: item.text) : nil, from: item)
    }

    /// Puts a colour clip on the pasteboard in another notation.
    @discardableResult
    private func copyColor(of item: ClipItem, as format: ClipColor.Format) -> Bool {
        let color = item.kind == .color && !item.isEncrypted
            ? ClipColor.parse(item.text, allowingBareHex: true) : nil
        return derive(color?.formatted(as: format), from: item)
    }

    /// Copies the text of several clips as one new clip, one clip per line, in the given order.
    @discardableResult
    private func copyCombined(_ items: [ClipItem]) -> Bool {
        let texts = items
            .filter { ($0.kind == .text || $0.kind == .link || $0.kind == .color) && !$0.isEncrypted }
            .map(\.text)
        guard let first = items.first else { return false }
        return derive(texts.isEmpty ? nil : texts.joined(separator: "\n"), from: first)
    }

    /// Stores text made from a clip as the newest clip and puts it on the pasteboard; the
    /// original clip stays. Beeps and returns false when there is no text.
    private func derive(_ text: String?, from item: ClipItem) -> Bool {
        guard let text, let added = add(.text(text), rich: nil, source: item.source), copy(added) else {
            NSSound.beep()
            return false
        }
        confirmCopy()
        return true
    }

    /// The sound for a copy or a paste made from the app, at the volume the user chose.
    private func playFeedbackSound() {
        guard settings.copyFeedback, let sound = NSSound(named: settings.copySound.systemName) else { return }
        // A sound object plays once at a time; a copy of it lets quick repeats overlap.
        let instance = (sound.copy() as? NSSound) ?? sound
        instance.volume = Float(settings.copySoundVolume)
        instance.play()
    }

    // MARK: - Editing and opening

    private let editors = ClipEditorWindows()

    /// Opens the window where the clip's title, and for text its content, can be changed.
    private func edit(_ item: ClipItem) {
        guard !item.isEncrypted else {
            NSSound.beep()
            return
        }
        hidePanel()
        notch.close()
        editors.open(item) { [weak self] title, text in
            guard let self, let store = self.store else { return L10n.string("clipboard.edit.failed") }
            do {
                if item.isTextEditable {
                    switch try store.updateText(id: item.id, text: text, at: Date()) {
                    case .updated, .unchanged: break
                    case .duplicate: return L10n.string("clipboard.edit.duplicate")
                    case .notEditable: return L10n.string("clipboard.edit.empty")
                    }
                }
                try store.setTitle(id: item.id, title: title)
            } catch {
                return L10n.string("clipboard.edit.failed")
            }
            self.reload()
            return nil
        }
    }

    /// The file behind a clip: the first file of a file clip, or the stored picture of an image clip.
    private func fileURL(of item: ClipItem) -> URL? {
        guard !item.isEncrypted else { return nil }
        switch item.kind {
        case .file:
            return item.filePaths.first.map { URL(fileURLWithPath: $0) }
        case .image:
            return store?.imageFileURL(for: item)
        case .text, .link, .color:
            return nil
        }
    }

    /// Opens a link in the browser, a file or a picture in its default app or in the given one.
    private func open(_ item: ClipItem, with app: URL? = nil) {
        let target: URL?
        if item.kind == .link {
            target = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            target = fileURL(of: item)
        }
        guard let target, target.isFileURL || ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
            NSSound.beep()
            return
        }
        dismiss()
        if let app {
            NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    /// Opens the editor for the newest text clip; for automated checks.
    public func editNewestText() {
        if let item = viewModel.items.first(where: { $0.isTextEditable }) {
            edit(item)
        }
    }

    // MARK: - Text in images

    /// Reads the text in a picture and answers on the main actor; set by the app, so this
    /// module does not need the text recognition framework itself.
    public var recognizeText: ((_ imageData: Data, _ completion: @escaping @MainActor (String) -> Void) -> Void)?
    private var isReadingImage = false

    /// Reads the text of image clips that were not read yet, one at a time, newest first.
    private func readTextInImagesIfNeeded() {
        guard settings.readsTextInImages, !isReadingImage, let recognizeText, let store,
              let item = try? store.imagesAwaitingRecognition(limit: 1).first
        else { return }
        guard let data = store.imageData(for: item) else {
            // A picture whose file is gone has no text to read; do not try it again.
            perform { try $0.setRecognizedText(id: item.id, text: "") }
            readTextInImagesIfNeeded()
            return
        }
        isReadingImage = true
        recognizeText(data) { [weak self] text in
            guard let self else { return }
            self.isReadingImage = false
            self.perform { try $0.setRecognizedText(id: item.id, text: text) }
            self.readTextInImagesIfNeeded()
        }
    }

    // MARK: - Notes, reminders, pictures, the on-device model

    /// Makes a macOS reminder; set by the app, which has the calendar feature do it. The
    /// answer says whether the reminder was made.
    public var createReminder: ((_ title: String, _ notes: String?, _ due: Date, _ completion: @escaping @MainActor (Bool) -> Void) -> Void)? {
        didSet { viewModel.canRemind = createReminder != nil }
    }

    private func remind(_ item: ClipItem, _ preset: ClipReminderPreset) {
        remind(item, due: preset.due(from: Date(), calendar: .current))
    }

    /// Lets the day and the time of the reminder be chosen on a month and a clock face.
    private func remindAtChosenTime(_ item: ClipItem) {
        guard createReminder != nil else { return }
        let calendar = Calendar.current
        let nextHour = calendar.date(
            byAdding: .hour, value: 1, to: calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()) ?? Date()
        AraMomentPicker.shared.present(
            title: ClipReminderText.title(for: item, fallback: item.rowTitle), initial: nextHour
        ) { [weak self] due in
            self?.remind(item, due: due)
        }
    }

    private func remind(_ item: ClipItem, due: Date) {
        guard let createReminder else { return }
        let title = ClipReminderText.title(for: item, fallback: item.rowTitle)
        createReminder(title, ClipReminderText.notes(for: item), due) { [weak self] made in
            guard made else {
                NSSound.beep()
                self?.announce(symbol: "bell.slash", L10n.string("clipboard.remind.failed"))
                return
            }
            let formatter = DateFormatter()
            formatter.dateStyle = Calendar.current.isDateInToday(due) ? .none : .short
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            self?.announce(
                symbol: "bell.fill", String(format: L10n.string("clipboard.remind.made"), formatter.string(from: due)))
        }
    }

    /// Cuts the subject of a picture out of its background; set by the app. Answers with PNG
    /// data, or nil when no subject was found.
    public var cutOutSubject: ((_ imageData: Data, _ completion: @escaping @MainActor (Data?) -> Void) -> Void)?

    private func removeBackground(of item: ClipItem) {
        guard let cutOutSubject, let data = store?.imageData(for: item) else {
            NSSound.beep()
            return
        }
        announce(symbol: "person.and.background.dotted", L10n.string("clipboard.image.working"))
        cutOutSubject(data) { [weak self] result in
            guard let self else { return }
            guard let result, let added = self.add(.image(result), rich: nil, source: item.source), self.copy(added) else {
                NSSound.beep()
                self.announce(symbol: "person.and.background.dotted", L10n.string("clipboard.image.noSubject"))
                return
            }
            self.confirmCopy()
        }
    }

    /// Saves a picture clip to a file of the user's choosing, in the given format.
    private func saveImage(_ item: ClipItem, format: String) {
        guard let data = store?.imageData(for: item), let converted = ClipImageExport.data(from: data, format: format) else {
            NSSound.beep()
            return
        }
        hidePanel()
        notch.close()
        let panel = NSSavePanel()
        let fileExtension = format == "jpeg" ? "jpg" : format
        panel.nameFieldStringValue = "\(item.title ?? L10n.string("clipboard.kind.image")).\(fileExtension)"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try converted.write(to: url)
        } catch {
            NSSound.beep()
        }
    }

    /// Runs the on-device model on text; set by the app. Answers with the new text, or nil.
    public var assistant: ((_ action: String, _ text: String, _ completion: @escaping @MainActor (String?) -> Void) -> Void)?
    /// The actions the on-device model can do right now; empty hides the menu.
    public var assistantActions: [String] = [] {
        didSet { viewModel.assistantActions = assistantActions }
    }

    private func assist(_ item: ClipItem, action: String) {
        guard let assistant, item.kind == .text, !item.isEncrypted else { return }
        announce(symbol: "sparkles", L10n.string("clipboard.assist.working"), duration: 20)
        assistant(action, item.text) { [weak self] result in
            guard let self else { return }
            guard let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep()
                self.announce(symbol: "sparkles", L10n.string("clipboard.assist.failed"))
                return
            }
            // The answer becomes the newest clip and is on the pasteboard; the original stays.
            _ = self.derive(result, from: item)
        }
    }

    /// A short notice beside the notch.
    private func announce(symbol: String, _ message: String, duration: TimeInterval = 2.5) {
        notch.present(NotchLiveActivity(
            id: "clipboard.notice", priority: 1, duration: duration, pageID: "clipboard",
            sign: AraSign(icon: .symbol(symbol), mark: "Clipboard", rows: [AraSign.Row(message)])))
    }

    // MARK: - Pasting pinned clips by number

    /// Pastes clip number 1…9 of the quick-paste board into the app in front.
    private func quickPaste(number: Int) {
        let boards = viewModel.boards
        let board = boards.first { $0.name == settings.quickPasteBoardName } ?? boards.first
        guard let board, let store,
              !(board.isLocked && viewModel.vaultState != .unlocked),
              let items = try? store.items(inBoard: board.id), items.indices.contains(number - 1),
              copy(items[number - 1])
        else {
            NSSound.beep()
            return
        }
        playFeedbackSound()
        guard Paster.isTrusted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Paster.pasteIntoFrontmostApp()
        }
    }

    /// Hides the clip at once and deletes it for real a few seconds later, unless the
    /// deletion is undone in between.
    private func delete(_ item: ClipItem) {
        viewModel.copyStack.remove(item.id)
        pendingDeletions.add([item.id], at: Date())
        pendingDeletionsChanged()
    }

    private func undoDelete() {
        guard !pendingDeletions.undoLast().isEmpty else { return }
        AraHaptics.play(.change)
        pendingDeletionsChanged()
    }

    /// Deletes for real every clip whose time to be undone is over, or all of them when
    /// there will be no later.
    public func flushPendingDeletions(all: Bool = false) {
        let ids = all ? pendingDeletions.takeAll() : pendingDeletions.takeDue(at: Date())
        guard !ids.isEmpty, let store else {
            pendingDeletionsChanged()
            return
        }
        for id in ids {
            if let item = try? store.item(id: id) {
                for blobName in [item.blobName, item.linkImageBlobName].compactMap({ $0 }) {
                    // A picture is kept at a card's size and at the preview's.
                    for key in [blobName, "\(ClipThumbnail.cardPixelSize)/\(blobName)", "\(ClipThumbnail.maxPixelSize)/\(blobName)"] {
                        thumbnails.removeObject(forKey: key as NSString)
                    }
                }
            }
            do {
                try store.delete(id: id)
            } catch {
                log.error("clipboard history error: \(String(describing: error), privacy: .public)")
            }
        }
        pendingDeletionsChanged()
    }

    private func pendingDeletionsChanged() {
        viewModel.undoableDeletionCount = pendingDeletions.latestCount
        deletionTimer?.invalidate()
        deletionTimer = nil
        if let deadline = pendingDeletions.nextDeadline {
            let timer = Timer(timeInterval: max(deadline.timeIntervalSinceNow, 0) + 0.05, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushPendingDeletions() }
            }
            RunLoop.main.add(timer, forMode: .common)
            deletionTimer = timer
        }
        reload()
    }

    // MARK: - Quick Look

    /// Shows the clip in the system's Quick Look panel: a picture or a file as it is, text
    /// as a text file written for the occasion.
    private func preview(_ item: ClipItem) {
        if AraQuickLook.shared.isShowing {
            AraQuickLook.shared.close()
            return
        }
        let urls = previewURLs(for: item)
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        isOpeningPreview = true
        AraQuickLook.shared.show(urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.isOpeningPreview = false }
    }

    private func previewURLs(for item: ClipItem) -> [URL] {
        guard !item.isEncrypted else { return [] }
        switch item.kind {
        case .image:
            return [store?.imageFileURL(for: item)].compactMap { $0 }
        case .file:
            return item.filePaths.map { URL(fileURLWithPath: $0) }
        case .text, .link, .color:
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AraNotch-preview", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rich = store?.richData(for: item)
            // Named after the clip, since Quick Look shows the file's name as its title.
            let words = item.rowTitle.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\r\t")).joined(separator: " ")
            let title = String(words.trimmingCharacters(in: .whitespaces).prefix(40))
            let name = title.isEmpty ? "clip-\(item.id)" : title
            if let rtf = rich?.rtf, !rtf.isEmpty {
                let url = directory.appendingPathComponent(name + ".rtf")
                return (try? rtf.write(to: url)) != nil ? [url] : []
            }
            let url = directory.appendingPathComponent(name + ".txt")
            return (try? Data(item.text.utf8).write(to: url)) != nil ? [url] : []
        }
    }

    /// A copy of the picture no larger than a card needs, or than the large preview needs.
    private func thumbnail(for item: ClipItem, maxPixelSize: Int = ClipThumbnail.cardPixelSize) -> NSImage? {
        guard let blobName = item.blobName else { return nil }
        let key = "\(maxPixelSize)/\(blobName)"
        if let cached = thumbnails.object(forKey: key as NSString) { return cached }
        guard let data = store?.imageData(for: item) else { return nil }
        return cachedThumbnail(of: data, key: key, maxPixelSize: maxPixelSize)
    }

    /// A small copy of the picture, decoded once and kept in the cache at what it costs.
    private func cachedThumbnail(
        of data: Data, key: String, maxPixelSize: Int = ClipThumbnail.cardPixelSize
    ) -> NSImage? {
        guard let small = ClipThumbnail.image(from: data, maxPixelSize: maxPixelSize) else { return nil }
        let image = NSImage(cgImage: small, size: NSSize(width: small.width, height: small.height))
        thumbnails.setObject(image, forKey: key as NSString, cost: ClipThumbnail.cost(of: small))
        return image
    }

    // MARK: - Store access

    /// Runs a store operation and refreshes the page. A failure is logged, never fatal.
    private func perform(_ operation: (ClipboardStore) throws -> Void) {
        guard let store else { return }
        do {
            try operation(store)
        } catch {
            log.error("clipboard history error: \(String(describing: error), privacy: .public)")
        }
        reload()
    }

    private func reload() {
        guard let store else { return }
        do {
            // Clips deleted a moment ago are left out while the deletion can still be undone.
            let hidden = pendingDeletions.hiddenIDs
            viewModel.items = try store.items().filter { !hidden.contains($0.id) }
            viewModel.boards = try store.boards()
            viewModel.membership = try store.boardMembership()
            viewModel.vaultState = store.vaultState
            // A board that no longer exists, or is locked again, falls back to the whole history.
            if let selected = viewModel.selectedBoardID {
                let board = viewModel.boards.first { $0.id == selected }
                if board == nil || (board?.isLocked == true && store.vaultState != .unlocked) {
                    viewModel.selectedBoardID = nil
                }
            }
            viewModel.boardItems = try viewModel.selectedBoardID
                .map { try store.items(inBoard: $0).filter { !hidden.contains($0.id) } } ?? []
        } catch {
            log.error("cannot read clipboard history: \(String(describing: error), privacy: .public)")
        }
    }
}
