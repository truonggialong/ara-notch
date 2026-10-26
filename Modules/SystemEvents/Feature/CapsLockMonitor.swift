import AppKit

/// Reports the Caps Lock state. With Accessibility permission it is told by the system when a
/// modifier key changes, and costs nothing in between; without it, watching keys is not
/// allowed, so it reads the modifier flags a few times a second instead.
@MainActor
final class CapsLockMonitor {
    static let interval: TimeInterval = 0.3

    var onRead: ((Bool) -> Void)?

    private var timer: Timer?
    private var monitors: [Any] = []

    static var isOn: Bool {
        NSEvent.modifierFlags.contains(.capsLock)
    }

    func start() {
        guard timer == nil, monitors.isEmpty else { return }
        if AXIsProcessTrusted() {
            let report: (NSEvent) -> Void = { [weak self] event in
                MainActor.assumeIsolated { self?.onRead?(event.modifierFlags.contains(.capsLock)) }
            }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: report) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
                report(event)
                return event
            }) {
                monitors.append(local)
            }
        }
        if monitors.isEmpty {
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onRead?(Self.isOn) }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        onRead?(Self.isOn)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
