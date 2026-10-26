import Foundation

/// Reads and writes the shell's settings. Missing, mistyped or out-of-range values fall back safely.
public struct ShellSettingsStore {
    public enum Key {
        public static let openOnHover = "shell.openOnHover"
        public static let hoverDelay = "shell.hoverDelay"
        public static let hapticsEnabled = "shell.hapticsEnabled"
        public static let pageOrder = "shell.pageOrder"
        public static let hiddenPages = "shell.hiddenPages"
        public static let startPage = "shell.startPage"
        public static let hidesFromCapture = "shell.hidesFromCapture"
        public static let swipeToOpen = "shell.swipeToOpen"
        public static let swipeSensitivity = "shell.swipeSensitivity"
        public static let interactionPadding = "shell.interactionPadding"
        public static let displayMode = "shell.displayMode"
        public static let hidesInFullScreen = "shell.hidesInFullScreen"
        public static let pillStyle = "shell.pillStyle"
        public static let notchSize = "shell.notchSize"
        public static let appearance = "shell.appearance"
        public static let hasSeenWelcome = "shell.hasSeenWelcome"
        /// Where the look of the clipboard panel alone used to be kept.
        static let legacyPanelAppearance = "clipboard.panelAppearance"
    }

    public static let hoverDelayRange: ClosedRange<Double> = 0...0.5
    public static let defaultHoverDelay: Double = 0.10
    /// Points added around the closed notch for hovering, clicking and swiping.
    public static let interactionPaddingRange: ClosedRange<Double> = 0...24
    public static let defaultInteractionPadding: Double = 4
    /// Seconds the panel stays open after the pointer leaves it. Not user-configurable.
    public static let closeDelay: Double = 0.25

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var openOnHover: Bool {
        get { bool(forKey: Key.openOnHover, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.openOnHover) }
    }

    public var hoverDelay: Double {
        get {
            guard let value = defaults.object(forKey: Key.hoverDelay) as? Double, !value.isNaN else {
                return Self.defaultHoverDelay
            }
            return Self.clamp(value)
        }
        nonmutating set {
            if newValue.isNaN {
                defaults.removeObject(forKey: Key.hoverDelay)
            } else {
                defaults.set(Self.clamp(newValue), forKey: Key.hoverDelay)
            }
        }
    }

    public var hapticsEnabled: Bool {
        get { bool(forKey: Key.hapticsEnabled, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
    }

    /// Page ids in the order their tabs are shown; pages not listed follow in their built-in order.
    public var pageOrder: [String] {
        get { defaults.object(forKey: Key.pageOrder) as? [String] ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.pageOrder) }
    }

    /// Ids of the pages whose tabs are hidden.
    public var hiddenPages: [String] {
        get { defaults.object(forKey: Key.hiddenPages) as? [String] ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.hiddenPages) }
    }

    /// The page shown each time the notch opens; nil keeps the page that was last used.
    public var startPage: String? {
        get { defaults.object(forKey: Key.startPage) as? String }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Key.startPage)
            } else {
                defaults.removeObject(forKey: Key.startPage)
            }
        }
    }

    /// Keep the app's windows out of screenshots, recordings and screen sharing.
    public var hidesFromCapture: Bool {
        get { bool(forKey: Key.hidesFromCapture, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.hidesFromCapture) }
    }

    /// A two-finger swipe down on the closed notch opens it; a swipe up on its tab row closes it.
    public var swipeToOpen: Bool {
        get { bool(forKey: Key.swipeToOpen, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.swipeToOpen) }
    }

    public var swipeSensitivity: SwipeSensitivity {
        get { (defaults.object(forKey: Key.swipeSensitivity) as? String).flatMap(SwipeSensitivity.init) ?? .medium }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.swipeSensitivity) }
    }

    public var interactionPadding: Double {
        get {
            guard let value = defaults.object(forKey: Key.interactionPadding) as? Double, !value.isNaN else {
                return Self.defaultInteractionPadding
            }
            return min(max(value, Self.interactionPaddingRange.lowerBound), Self.interactionPaddingRange.upperBound)
        }
        nonmutating set {
            let clamped = min(max(newValue, Self.interactionPaddingRange.lowerBound), Self.interactionPaddingRange.upperBound)
            defaults.set(clamped, forKey: Key.interactionPadding)
        }
    }

    /// Which display shows the notch when several are connected.
    /// On a display without a hardware notch, draw a floating capsule instead of a notch shape.
    public var pillStyle: Bool {
        get { defaults.object(forKey: Key.pillStyle) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.pillStyle) }
    }

    /// How large the notch opens.
    /// The look of the app's windows. The notch itself is always dark, like the hardware.
    public var appearance: AppAppearance {
        get {
            let stored = defaults.string(forKey: Key.appearance) ?? defaults.string(forKey: Key.legacyPanelAppearance)
            return stored.flatMap(AppAppearance.init) ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    /// Whether the first-run guide has been shown.
    public var hasSeenWelcome: Bool {
        get { defaults.bool(forKey: Key.hasSeenWelcome) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasSeenWelcome) }
    }

    public var notchSize: NotchSize {
        get { (defaults.object(forKey: Key.notchSize) as? String).flatMap(NotchSize.init(storedName:)) ?? .standard }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.notchSize) }
    }

    /// The notch keeps out of the way of an app that is full screen on its display.
    public var hidesInFullScreen: Bool {
        get { defaults.object(forKey: Key.hidesInFullScreen) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.hidesInFullScreen) }
    }

    public var displayMode: DisplayMode {
        get { (defaults.object(forKey: Key.displayMode) as? String).flatMap(DisplayMode.init) ?? .all }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }
}
