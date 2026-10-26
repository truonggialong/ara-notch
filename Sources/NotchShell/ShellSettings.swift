import Combine
import NotchCore

/// Observable settings for the shell; every change is written through to the store.
@MainActor
public final class ShellSettings: ObservableObject {
    private let store: ShellSettingsStore

    @Published public var openOnHover: Bool {
        didSet { store.openOnHover = openOnHover }
    }

    @Published public var hoverDelay: Double {
        didSet { store.hoverDelay = hoverDelay }
    }

    @Published public var hapticsEnabled: Bool {
        didSet { store.hapticsEnabled = hapticsEnabled }
    }

    @Published public var pageOrder: [String] {
        didSet { store.pageOrder = pageOrder }
    }

    @Published public var hiddenPages: [String] {
        didSet { store.hiddenPages = hiddenPages }
    }

    @Published public var startPage: String? {
        didSet { store.startPage = startPage }
    }

    @Published public var hidesFromCapture: Bool {
        didSet { store.hidesFromCapture = hidesFromCapture }
    }

    @Published public var hidesInFullScreen: Bool {
        didSet { store.hidesInFullScreen = hidesInFullScreen }
    }

    @Published public var swipeToOpen: Bool {
        didSet { store.swipeToOpen = swipeToOpen }
    }

    @Published public var swipeSensitivity: SwipeSensitivity {
        didSet { store.swipeSensitivity = swipeSensitivity }
    }

    @Published public var interactionPadding: Double {
        didSet { store.interactionPadding = interactionPadding }
    }

    @Published public var pillStyle: Bool {
        didSet { store.pillStyle = pillStyle }
    }

    @Published public var notchSize: NotchSize {
        didSet { store.notchSize = notchSize }
    }

    @Published public var displayMode: DisplayMode {
        didSet { store.displayMode = displayMode }
    }

    /// The look of the app's windows; the notch stays dark.
    @Published public var appearance: AppAppearance {
        didSet { store.appearance = appearance }
    }

    /// Whether the first-run guide has been shown.
    public var hasSeenWelcome: Bool {
        get { store.hasSeenWelcome }
        set { store.hasSeenWelcome = newValue }
    }

    public init(store: ShellSettingsStore) {
        self.store = store
        openOnHover = store.openOnHover
        hoverDelay = store.hoverDelay
        hapticsEnabled = store.hapticsEnabled
        pageOrder = store.pageOrder
        hiddenPages = store.hiddenPages
        startPage = store.startPage
        hidesFromCapture = store.hidesFromCapture
        hidesInFullScreen = store.hidesInFullScreen
        swipeToOpen = store.swipeToOpen
        swipeSensitivity = store.swipeSensitivity
        interactionPadding = store.interactionPadding
        displayMode = store.displayMode
        notchSize = store.notchSize
        pillStyle = store.pillStyle
        appearance = store.appearance
    }
}
