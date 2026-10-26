import AppKit
import NotchShell

/// Feeds key presses in this app's windows to a handler before the focused view sees them.
/// The handler returns true to consume the key.
@MainActor
final class KeyCommandRouter {
    private var monitor: Any?

    func start(handler: @escaping (NSEvent) -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // A word still being composed by the input method gets its keys first.
            guard !event.isForInputMethod else { return event }
            return handler(event) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
