import Foundation

/// How long unpinned clips are kept before they are deleted automatically.
public enum ClipRetention: String, CaseIterable, Sendable {
    case never
    case day
    case week
    case month
    case year

    /// Clips last used before this moment have expired; nil when clips are kept forever.
    public func cutoff(from now: Date) -> Date? {
        let days: Double
        switch self {
        case .never: return nil
        case .day: days = 1
        case .week: days = 7
        case .month: days = 30
        case .year: days = 365
        }
        return now.addingTimeInterval(-days * 86_400)
    }
}

/// Reads and writes the clipboard settings. Missing, mistyped or out-of-range values fall back safely.
public struct ClipboardSettingsStore {
    public enum Key {
        public static let isPaused = "clipboard.isPaused"
        public static let maxItems = "clipboard.maxItems"
        public static let pasteOnClick = "clipboard.pasteOnClick"
        public static let ignoredBundleIDs = "clipboard.ignoredBundleIDs"
        public static let hotKeyEnabled = "clipboard.hotKeyEnabled"
        public static let vaultTouchID = "clipboard.vaultTouchID"
        public static let linkPreviews = "clipboard.linkPreviews"
        public static let bareHexColors = "clipboard.bareHexColors"
        public static let copyStackOrder = "clipboard.copyStackOrder"
        public static let panelAppearance = "clipboard.panelAppearance"
        public static let copySound = "clipboard.copySound"
        public static let savedFilters = "clipboard.savedFilters"
        public static let sortOrder = "clipboard.sortOrder"
        public static let pausedUntil = "clipboard.pausedUntil"
        public static let skipsSensitiveText = "clipboard.skipsSensitiveText"
        public static let readsTextInImages = "clipboard.readsTextInImages"
        public static let copySoundVolume = "clipboard.copySoundVolume"
        public static let quickPasteBoardName = "clipboard.quickPasteBoardName"
        /// Also read by the `aranotch-mcp` helper, by this exact name.
        public static let mcpEnabled = "clipboard.mcpEnabled"
        public static let retention = "clipboard.retention"
        public static let copyFeedback = "clipboard.copyFeedback"
        public static let copySign = "clipboard.copySign"
        public static let excludedFromBackup = "clipboard.excludedFromBackup"
    }

    public static let maxItemsRange: ClosedRange<Int> = 50...1000
    public static let defaultMaxItems = 500

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var isPaused: Bool {
        get { defaults.object(forKey: Key.isPaused) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    public var maxItems: Int {
        get {
            guard let value = defaults.object(forKey: Key.maxItems) as? Int else { return Self.defaultMaxItems }
            return Self.clamp(value)
        }
        nonmutating set { defaults.set(Self.clamp(newValue), forKey: Key.maxItems) }
    }

    /// When on, clicking an item pastes it into the frontmost app instead of only copying it.
    public var pasteOnClick: Bool {
        get { defaults.object(forKey: Key.pasteOnClick) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.pasteOnClick) }
    }

    /// Whether the global shortcut that opens the clipboard panel is registered.
    /// Locked boards may be opened with a fingerprint, which means keeping their passcode
    /// where the app can read it back. Off until the user turns it on.
    public var vaultTouchID: Bool {
        get { defaults.object(forKey: Key.vaultTouchID) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.vaultTouchID) }
    }

    public var hotKeyEnabled: Bool {
        get { defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.hotKeyEnabled) }
    }

    /// Whether copied links are fetched once to show their page title and image.
    /// The history is left out of Time Machine backups unless the user puts it back.
    public var excludedFromBackup: Bool {
        get { defaults.object(forKey: Key.excludedFromBackup) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.excludedFromBackup) }
    }

    public var linkPreviews: Bool {
        get { defaults.object(forKey: Key.linkPreviews) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.linkPreviews) }
    }

    /// Which stacked clip a paste takes first.
    public static let copySoundVolumeRange: ClosedRange<Double> = 0.05...1

    /// Searches the user saved to come back to, oldest first.
    public var savedFilters: [SavedFilter] {
        get { (defaults.stringArray(forKey: Key.savedFilters) ?? []).map(SavedFilter.init(query:)) }
        nonmutating set { defaults.set(newValue.map(\.query), forKey: Key.savedFilters) }
    }

    /// The order the history is listed in.
    public var sortOrder: ClipSortOrder {
        get { (defaults.object(forKey: Key.sortOrder) as? String).flatMap(ClipSortOrder.init) ?? .recentlyUsed }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.sortOrder) }
    }

    /// When a timed pause ends; nil when there is none.
    public var pausedUntil: Date? {
        get { (defaults.object(forKey: Key.pausedUntil) as? Double).map(Date.init(timeIntervalSince1970:)) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Key.pausedUntil)
            } else {
                defaults.removeObject(forKey: Key.pausedUntil)
            }
        }
    }

    /// Whether recording is paused at a moment: by the open-ended switch, or by a timed pause
    /// that has not run out.
    public func isPaused(at date: Date) -> Bool {
        if isPaused { return true }
        return pausedUntil.map { date < $0 } ?? false
    }

    /// Leave out copies that are a secret key, a private key or a card number.
    public var skipsSensitiveText: Bool {
        get { defaults.object(forKey: Key.skipsSensitiveText) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.skipsSensitiveText) }
    }

    /// Read the text in copied images, on this Mac, so they can be found by it.
    public var readsTextInImages: Bool {
        get { defaults.object(forKey: Key.readsTextInImages) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.readsTextInImages) }
    }

    /// The sound played when a clip is copied or pasted from the app (when feedback is on).
    public var copySound: CopySound {
        get { (defaults.object(forKey: Key.copySound) as? String).flatMap(CopySound.init) ?? .tink }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.copySound) }
    }

    /// How loud that sound is, 0.05…1 of the system volume. Half by default: it plays often.
    public var copySoundVolume: Double {
        get {
            guard let value = defaults.object(forKey: Key.copySoundVolume) as? Double, !value.isNaN else { return 0.5 }
            return min(max(value, Self.copySoundVolumeRange.lowerBound), Self.copySoundVolumeRange.upperBound)
        }
        nonmutating set {
            let clamped = min(max(newValue, Self.copySoundVolumeRange.lowerBound), Self.copySoundVolumeRange.upperBound)
            defaults.set(clamped, forKey: Key.copySoundVolume)
        }
    }

    /// The board whose clips are pasted by number with a global shortcut; nil for the first board.
    public var quickPasteBoardName: String? {
        get { defaults.string(forKey: Key.quickPasteBoardName) }
        nonmutating set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Key.quickPasteBoardName)
            } else {
                defaults.removeObject(forKey: Key.quickPasteBoardName)
            }
        }
    }

    /// Whether the floating panel is dark, light, or follows the system.
    public var panelAppearance: PanelAppearance {
        get { (defaults.object(forKey: Key.panelAppearance) as? String).flatMap(PanelAppearance.init) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.panelAppearance) }
    }

    public var copyStackOrder: CopyStack.Order {
        get { (defaults.object(forKey: Key.copyStackOrder) as? String).flatMap(CopyStack.Order.init) ?? .firstCopiedFirst }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.copyStackOrder) }
    }

    /// Let AI agents read the history through the `aranotch-mcp` helper. Off by default.
    public var mcpEnabled: Bool {
        get { defaults.object(forKey: Key.mcpEnabled) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.mcpEnabled) }
    }

    /// Treat six or eight hex digits without `#` as a colour. Off by default: such text is
    /// often something else.
    public var bareHexColors: Bool {
        get { defaults.object(forKey: Key.bareHexColors) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.bareHexColors) }
    }

    public var retention: ClipRetention {
        get { (defaults.object(forKey: Key.retention) as? String).flatMap(ClipRetention.init(rawValue:)) ?? .never }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.retention) }
    }

    /// Whether a sound and a short notch notice confirm each copy, and a sound each paste.
    public var copyFeedback: Bool {
        get { defaults.object(forKey: Key.copyFeedback) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.copyFeedback) }
    }

    /// The "Copied" sign beside the notch after a copy. Until it is chosen, as the sound is:
    /// one setting gave both until 0.23.0.
    public var copySign: Bool {
        get { defaults.object(forKey: Key.copySign) as? Bool ?? copyFeedback }
        nonmutating set { defaults.set(newValue, forKey: Key.copySign) }
    }

    /// Bundle identifiers of apps whose copies are never recorded.
    public var ignoredBundleIDs: [String] {
        get { Self.clean(defaults.object(forKey: Key.ignoredBundleIDs) as? [String] ?? []) }
        nonmutating set { defaults.set(Self.clean(newValue), forKey: Key.ignoredBundleIDs) }
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, maxItemsRange.lowerBound), maxItemsRange.upperBound)
    }

    /// Trims, drops empty entries and removes duplicates while keeping the order.
    private static func clean(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// How the floating clipboard panel looks.
public enum PanelAppearance: String, CaseIterable, Sendable {
    case system
    case dark
    case light

    public func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: systemIsDark
        case .dark: true
        case .light: false
        }
    }
}

/// The sounds offered as copy feedback; each is a sound that ships with macOS.
public enum CopySound: String, CaseIterable, Sendable {
    case tink
    case pop
    case morse
    case purr
    case bottle

    /// The name macOS knows the sound by.
    public var systemName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

