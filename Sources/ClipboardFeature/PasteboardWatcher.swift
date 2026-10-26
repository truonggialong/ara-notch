import AppKit
import ClipboardCore

/// Notices when the pasteboard changes. macOS offers no notification for this, so it polls
/// the change counter, which is cheap.
@MainActor
final class PasteboardWatcher {
    /// Copies closer together than this are seen as one: at half a second, three of four copies
    /// made in quick succession were lost.
    static let interval: TimeInterval = 0.25

    /// Called when the pasteboard should be read. Return false when nothing readable was there
    /// yet, so the read is tried again shortly.
    var onChange: (() -> Bool)?

    private let pasteboard: NSPasteboard
    private var tracker: PasteboardChangeTracker
    private var timer: Timer?

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        tracker = PasteboardChangeTracker(changeCount: pasteboard.changeCount)
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after this app wrote to the pasteboard, so its own write is not recorded as a new copy.
    func ignoreCurrentContents() {
        tracker.ignore(changeCount: pasteboard.changeCount)
    }

    /// Checks the pasteboard right now instead of waiting for the next tick.
    func pollNow() {
        poll()
    }

    private func poll() {
        guard tracker.shouldRead(changeCount: pasteboard.changeCount) else { return }
        tracker.readFinished(foundContent: onChange?() ?? true)
    }
}
