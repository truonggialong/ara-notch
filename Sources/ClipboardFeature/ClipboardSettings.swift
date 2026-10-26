import Foundation
import ClipboardCore
import Combine

/// Observable clipboard settings; every change is written through to the store.
@MainActor
public final class ClipboardSettings: ObservableObject {
    private let store: ClipboardSettingsStore

    @Published public var isPaused: Bool {
        didSet { store.isPaused = isPaused }
    }

    @Published public var maxItems: Int {
        didSet { store.maxItems = maxItems }
    }

    @Published public var pasteOnClick: Bool {
        didSet { store.pasteOnClick = pasteOnClick }
    }

    @Published public var ignoredBundleIDs: [String] {
        didSet { store.ignoredBundleIDs = ignoredBundleIDs }
    }

    @Published public var vaultTouchID: Bool {
        didSet { store.vaultTouchID = vaultTouchID }
    }

    @Published public var hotKeyEnabled: Bool {
        didSet { store.hotKeyEnabled = hotKeyEnabled }
    }

    @Published public var linkPreviews: Bool {
        didSet { store.linkPreviews = linkPreviews }
    }

    @Published public var excludedFromBackup: Bool {
        didSet { store.excludedFromBackup = excludedFromBackup }
    }

    @Published public var retention: ClipRetention {
        didSet { store.retention = retention }
    }

    /// The sound after a copy and a paste made from the app.
    @Published public var copyFeedback: Bool {
        didSet { store.copyFeedback = copyFeedback }
    }

    /// The "Copied" sign beside the notch after a copy.
    @Published public var copySign: Bool {
        didSet { store.copySign = copySign }
    }

    @Published public var bareHexColors: Bool {
        didSet { store.bareHexColors = bareHexColors }
    }

    @Published public var mcpEnabled: Bool {
        didSet { store.mcpEnabled = mcpEnabled }
    }

    @Published public var panelAppearance: PanelAppearance {
        didSet { store.panelAppearance = panelAppearance }
    }

    @Published public var readsTextInImages: Bool {
        didSet { store.readsTextInImages = readsTextInImages }
    }

    /// When a timed pause ends; nil when there is none.
    @Published public var pausedUntil: Date? {
        didSet { store.pausedUntil = pausedUntil }
    }

    @Published public var skipsSensitiveText: Bool {
        didSet { store.skipsSensitiveText = skipsSensitiveText }
    }

    /// Recording is paused now, by the switch or by a timed pause that has not run out.
    public var isPausedNow: Bool {
        isPaused || (pausedUntil.map { Date() < $0 } ?? false)
    }

    @Published public var sortOrder: ClipSortOrder {
        didSet { store.sortOrder = sortOrder }
    }

    @Published public var savedFilters: [SavedFilter] {
        didSet { store.savedFilters = savedFilters }
    }

    @Published public var copySound: CopySound {
        didSet { store.copySound = copySound }
    }

    @Published public var copySoundVolume: Double {
        didSet { store.copySoundVolume = copySoundVolume }
    }

    /// Empty for the first board.
    @Published public var quickPasteBoardName: String {
        didSet { store.quickPasteBoardName = quickPasteBoardName.isEmpty ? nil : quickPasteBoardName }
    }

    @Published public var copyStackOrder: CopyStack.Order {
        didSet { store.copyStackOrder = copyStackOrder }
    }

    public init(store: ClipboardSettingsStore) {
        self.store = store
        isPaused = store.isPaused
        maxItems = store.maxItems
        pasteOnClick = store.pasteOnClick
        ignoredBundleIDs = store.ignoredBundleIDs
        vaultTouchID = store.vaultTouchID
        hotKeyEnabled = store.hotKeyEnabled
        linkPreviews = store.linkPreviews
        excludedFromBackup = store.excludedFromBackup
        retention = store.retention
        copyFeedback = store.copyFeedback
        copySign = store.copySign
        bareHexColors = store.bareHexColors
        mcpEnabled = store.mcpEnabled
        copyStackOrder = store.copyStackOrder
        copySound = store.copySound
        sortOrder = store.sortOrder
        savedFilters = store.savedFilters
        pausedUntil = store.pausedUntil
        skipsSensitiveText = store.skipsSensitiveText
        readsTextInImages = store.readsTextInImages
        copySoundVolume = store.copySoundVolume
        quickPasteBoardName = store.quickPasteBoardName ?? ""
        panelAppearance = store.panelAppearance
    }
}
