import AppKit
import WindowsCore

/// Watches for a window being dragged to an edge of the display, shows where it would snap,
/// and snaps it when the mouse button is released there.
@MainActor
final class EdgeSnapMonitor {
    private var monitors: [Any] = []
    private var overlay: NSPanel?
    /// Where the front window was when the drag began; nil until the first drag event.
    private var startOrigin: CGPoint?
    private var isMovingWindow = false
    private var lastCheck = Date.distantPast
    private var pending: (zone: SnapZone, screen: NSScreen)?

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        // Global only: this is about other apps' windows.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            reset()
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            let target = pending
            let moved = isMovingWindow
            reset()
            if moved, let target {
                // A moment later, so the app has finished its own handling of the drag.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    WindowMover.snap(to: target.zone, on: target.screen)
                }
            }
        default:
            break
        }
    }

    private func dragged() {
        // Asking another app where its window is takes a moment; a few times a second is plenty.
        let now = Date()
        if !isMovingWindow, now.timeIntervalSince(lastCheck) > 0.08 {
            lastCheck = now
            guard let origin = WindowMover.frontWindowOrigin() else { return }
            if let startOrigin {
                isMovingWindow = EdgeSnap.hasMoved(from: startOrigin, to: origin)
            } else {
                startOrigin = origin
            }
        }
        guard isMovingWindow else { return }

        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(pointer) }),
              let zone = EdgeSnap.zone(at: pointer, in: screen.frame)
        else {
            pending = nil
            overlay?.orderOut(nil)
            return
        }
        if pending?.zone != zone || pending?.screen != screen {
            pending = (zone, screen)
            showOverlay(at: zone.frame(in: screen.visibleFrame))
        }
    }

    private func reset() {
        startOrigin = nil
        isMovingWindow = false
        pending = nil
        lastCheck = .distantPast
        overlay?.orderOut(nil)
    }

    /// A translucent outline of the place the window will snap to.
    private func showOverlay(at frame: CGRect) {
        let panel = overlay ?? makeOverlay()
        panel.setFrame(frame.insetBy(dx: 6, dy: 6), display: true)
        panel.orderFrontRegardless()
    }

    private func makeOverlay() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 12
        panel.contentView = view
        overlay = panel
        return panel
    }
}
