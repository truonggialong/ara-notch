/// Decides when the notch opens and closes. Pure: the caller runs the returned effects.
public struct NotchStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case closed
        /// Pointer is on the closed notch and the hover delay is running.
        case hoverPending
        case open
        /// Pointer left the open panel and the close delay is running.
        case closePending
    }

    public enum Event: Equatable, Sendable {
        case pointerMoved(inside: Bool)
        case clicked(inside: Bool)
        case hoverDelayElapsed
        case closeDelayElapsed
        case forceOpen
        case forceClose
    }

    public enum Effect: Equatable, Sendable {
        case scheduleHoverTimer
        case cancelHoverTimer
        case scheduleCloseTimer
        case cancelCloseTimer
        case didOpen
        case didClose
    }

    public private(set) var state: State = .closed
    public var openOnHover: Bool
    /// True while a menu opened from the open panel is on screen. The pointer moving onto that
    /// menu, or choosing one of its items, is not the pointer leaving the panel.
    public var isMenuTracking = false
    /// Pinned by the user: the open panel stays whatever the pointer does, until it is
    /// unpinned or told to close.
    public var isPinned = false
    /// Set by the page on show while something is under way that ends with a button of its
    /// own, such as a day and a time being chosen: the panel stays as if pinned until then.
    public var isKeptOpen = false
    /// True while text is being written in the panel. The pointer wandering off is then not
    /// a reason to close; a click elsewhere still is.
    public var isTyping = false
    /// Set by the page on show while it is being edited, as the overview while its tiles are
    /// arranged. Like typing: the pointer leaving is not a reason to close; a click elsewhere is.
    public var isBeingEdited = false
    /// Set by `forceOpen`: the panel ignores the pointer being elsewhere until it has entered once.
    private var isHeld = false

    public init(openOnHover: Bool = true) {
        self.openOnHover = openOnHover
    }

    /// Keeps the open panel where it is until the pointer has come back to it once, as after a
    /// forced open. For when the pointer had to go elsewhere on the panel's own business.
    public mutating func hold() {
        guard state == .open else { return }
        isHeld = true
    }

    /// Pinned by the user or kept by its page: neither the pointer leaving nor a click
    /// elsewhere closes the panel.
    public var staysOpen: Bool {
        isPinned || isKeptOpen
    }

    /// True while the open panel is on screen, including during the close delay.
    public var isPresented: Bool {
        state == .open || state == .closePending
    }

    /// Any pair not listed leaves the state unchanged, so a timer that fires late is harmless.
    public mutating func handle(_ event: Event) -> [Effect] {
        let effects = transition(for: event)
        if event == .forceOpen {
            isHeld = true
        } else if state == .closed || event == .pointerMoved(inside: true) {
            isHeld = false
        }
        return effects
    }

    private mutating func transition(for event: Event) -> [Effect] {
        switch (state, event) {
        case (.closed, .pointerMoved(inside: true)) where openOnHover:
            state = .hoverPending
            return [.scheduleHoverTimer]
        case (.closed, .clicked(inside: true)), (.closed, .forceOpen):
            state = .open
            return [.didOpen]

        case (.hoverPending, .pointerMoved(inside: false)), (.hoverPending, .forceClose):
            state = .closed
            return [.cancelHoverTimer]
        case (.hoverPending, .hoverDelayElapsed):
            state = .open
            return [.didOpen]
        case (.hoverPending, .clicked(inside: true)), (.hoverPending, .forceOpen):
            state = .open
            return [.cancelHoverTimer, .didOpen]

        case (.open, .pointerMoved(inside: false)) where !isHeld && !isMenuTracking && !staysOpen && !isTyping && !isBeingEdited:
            state = .closePending
            return [.scheduleCloseTimer]
        case (.open, .clicked(inside: false)) where !isMenuTracking && !staysOpen:
            state = .closed
            return [.didClose]
        case (.open, .forceClose):
            state = .closed
            return [.didClose]

        case (.closePending, .pointerMoved(inside: true)), (.closePending, .forceOpen):
            state = .open
            return [.cancelCloseTimer]
        case (.closePending, .closeDelayElapsed) where !staysOpen && !isBeingEdited:
            state = .closed
            return [.didClose]
        case (.closePending, .clicked(inside: false)), (.closePending, .forceClose):
            state = .closed
            return [.cancelCloseTimer, .didClose]

        default:
            return []
        }
    }
}
