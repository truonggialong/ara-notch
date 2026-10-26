import AppKit

/// Reports pointer movement, clicks and scrolling, whichever app they are delivered to.
/// Needs no system permission.
@MainActor
final class PointerMonitor {
    /// Pointer location in global screen coordinates (bottom-left origin).
    var onMove: ((CGPoint) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    /// The pointer moved with the button held, carrying files (a drag out of Finder, say).
    var onFileDrag: ((CGPoint) -> Void)?
    /// Scroll events anywhere on screen; `event.window` is set only for this app's own windows.
    var onScroll: ((NSEvent) -> Void)?
    /// Asked for each scroll in this app's own windows: an event to deliver in its place, or
    /// nil to deliver it as it is.
    var rewriteScroll: ((NSEvent) -> NSEvent?)?

    private var monitors: [Any] = []
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var heldButtonTimer: Timer?

    func start() {
        guard monitors.isEmpty else { return }
        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]

        // Scrolling is watched everywhere too: a swipe on the closed notch lands on whatever is under it.
        let global = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents.union(.scrollWheel)) { [weak self] event in
            self?.dispatch(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union(.scrollWheel)) { [weak self] event in
            self?.dispatch(event)
            if event.type == .scrollWheel, let rewritten = self?.rewriteScroll?(event) {
                return rewritten
            }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        heldButtonTimer?.invalidate()
        heldButtonTimer = nil
    }

    /// While the button is held the pointer is followed by a timer: a drag session swallows
    /// the mouse events, in this app and in others, so monitors alone miss a drag over the notch.
    private func followHeldButton() {
        heldButtonTimer?.invalidate()
        // Often enough to catch a drag on its way up, before it is at the top of the screen.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard NSEvent.pressedMouseButtons & 1 == 1 else {
                    self.heldButtonTimer?.invalidate()
                    self.heldButtonTimer = nil
                    return
                }
                let location = NSEvent.mouseLocation
                self.onMove?(location)
                let drag = NSPasteboard(name: .drag)
                if drag.changeCount != self.dragChangeCount, drag.types?.contains(.fileURL) == true {
                    self.onFileDrag?(location)
                }
            }
        }
        // Common modes: a drag runs the run loop in event-tracking mode.
        RunLoop.main.add(timer, forMode: .common)
        heldButtonTimer = timer
    }

    private func dispatch(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // What the drag pasteboard holds now is left over from an earlier drag.
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            onClick?(NSEvent.mouseLocation)
            followHeldButton()
        case .scrollWheel:
            onScroll?(event)
        default:
            onMove?(NSEvent.mouseLocation)
        }
    }
}
