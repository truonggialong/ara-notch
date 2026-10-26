import AppKit
import CaptureCore
import os

private let log = Logger(subsystem: "com.aranotch.app", category: "capture")

/// Lets the user drag out a rectangle on the screen under the pointer.
@MainActor
final class RegionSelector {
    private var window: SelectorWindow?

    /// Answers with the rectangle in global display coordinates (origin at the top left of the
    /// main display, as the capture tool wants it), or nil when the user pressed Escape.
    func select(completion: @escaping @MainActor (CGRect?) -> Void) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            completion(nil)
            return
        }
        let window = SelectorWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = SelectorView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in
            self?.window?.orderOut(nil)
            self?.window = nil
            guard let rect else {
                completion(nil)
                return
            }
            // From the view's bottom-left coordinates to the global top-left ones.
            let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let global = CGRect(
                x: screen.frame.minX + rect.minX,
                y: mainHeight - (screen.frame.minY + rect.maxY),
                width: rect.width, height: rect.height)
            completion(global.integral)
        }
        window.contentView = view
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }
}

/// Borderless windows refuse the keyboard unless told otherwise; Escape must reach this one.
private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Dims the screen and draws the rectangle being dragged out.
private final class SelectorView: NSView {
    /// Smaller drags are taken for a slip of the hand.
    private static let minimumSide: CGFloat = 40

    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        guard let selection else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= Self.minimumSide, selection.height >= Self.minimumSide else {
            start = nil
            self.selection = nil
            needsDisplay = true
            return
        }
        onFinish?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    /// The other mouse button gives up too, for a hand that is on the mouse.
    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }
}

/// Turning frames into row numbers, and frames into one tall picture.
enum FrameRows {
    /// Column bands each row is split into for comparing frames.
    private static let bands = 16

    /// One signature per pixel row: the average brightness of each band. The outermost edges
    /// are left out: scroll bars live there and change between frames.
    static func signatures(of image: CGImage) -> [RowSignature] {
        let width = image.width, height = image.height
        guard width >= bands * 4, height > 0 else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        let first = Int(Double(width) * 0.04), last = Int(Double(width) * 0.92)
        let bandWidth = (last - first) / bands
        return pixels.withUnsafeBufferPointer { bytes in
            (0..<height).map { row in
                let base = row * width * 4
                return RowSignature(bands: (0..<bands).map { band in
                    var sum: UInt64 = 0
                    var index = base + (first + band * bandWidth) * 4
                    for _ in 0..<bandWidth {
                        sum += UInt64(bytes[index]) + UInt64(bytes[index + 1]) + UInt64(bytes[index + 2])
                        index += 4
                    }
                    return sum / UInt64(bandWidth * 3)
                })
            }
        }
    }

    /// The first frame whole, then the given number of bottom rows of each later frame.
    static func stitch(_ parts: [(image: CGImage, rows: Int)]) -> CGImage? {
        guard let width = parts.first?.image.width else { return nil }
        let height = parts.reduce(0) { $0 + $1.rows }
        guard height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The context's origin is at the bottom left; the picture is built from the top down.
        var top = height
        for part in parts {
            let source = CGRect(x: 0, y: part.image.height - part.rows, width: width, height: part.rows)
            guard let slice = part.image.cropping(to: source) else { continue }
            top -= part.rows
            context.draw(slice, in: CGRect(x: 0, y: top, width: width, height: part.rows))
        }
        return context.makeImage()
    }
}

/// A scrolling capture in progress: captures the region, scrolls it, captures again, and joins
/// the frames until the page stops moving. Escape stops early and keeps what was captured.
@MainActor
final class ScrollCaptureSession {
    /// Enough for very long pages; a guard against a page that never ends.
    private static let maximumFrames = 80
    /// Seconds for the page to settle after a scroll before the next frame is taken.
    private static let settleTime: TimeInterval = 0.6
    /// For automated checks: every frame is also written here as a PNG.
    static var framesDirectory: URL?

    private let rect: CGRect
    private let completion: @MainActor (CGImage?) -> Void
    private var stitcher = ScrollStitcher()
    private var parts: [(image: CGImage, rows: Int)] = []
    private var frames = 0
    private var stillFrames = 0
    private var isStopped = false
    private var escapeMonitor: Any?
    /// Lines to scroll per step. How far a line moves the page differs from app to app, so
    /// this starts small and is corrected after every frame.
    private var linesPerStep: Int32 = 2
    /// Which sign scrolls the page down. Normally the negative one; mouse software and the
    /// "natural scrolling" setting can turn it round, so it is found out by trying.
    private var direction: Int32 = -1
    private var hasTurnedRound = false
    private var hasMoved = false
    private var backFrames = 0
    private static let maximumBackFrames = 5

    init(rect: CGRect, completion: @escaping @MainActor (CGImage?) -> Void) {
        self.rect = rect
        self.completion = completion
    }

    func start() {
        // Escape stops early, and so does a click anywhere: the hand may be on the mouse.
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 {
                self?.isStopped = true
            }
        }
        captureNext()
    }

    private func captureNext() {
        ScreenCapturer.capture(rect: rect) { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.finish()
                return
            }
            self.frames += 1
            if let directory = Self.framesDirectory, let data = CaptureImage.pngData(image) {
                try? data.write(to: directory.appendingPathComponent("frame-\(self.frames).png"))
            }
            let addition = self.stitcher.add(FrameRows.signatures(of: image))
            log.notice("scrolling capture frame \(self.frames): \(String(describing: addition), privacy: .public), step \(self.direction * self.linesPerStep) lines")
            switch addition {
            case .first:
                self.parts.append((image, image.height))
            case .appended(let newRows):
                self.parts.append((image, newRows))
                self.stillFrames = 0
                self.hasMoved = true
                self.linesPerStep = Self.adjustedLines(self.linesPerStep, moved: newRows, frameHeight: image.height)
            case .noMovement:
                // One still frame may be a slow page; two in a row is the end of it. Before the
                // page has moved at all, it may be that the scroll went upwards from the top.
                self.stillFrames += 1
                if !self.hasMoved, !self.hasTurnedRound {
                    self.turnRound()
                }
            case .movedBack:
                // The scroll went the wrong way. After turning round it can take a few steps
                // to come back past the place where the page was; more than a few is a page
                // that will not go the right way.
                self.backFrames += 1
                if !self.hasTurnedRound {
                    self.turnRound()
                } else if self.backFrames > Self.maximumBackFrames {
                    self.isStopped = true
                }
            case .lost:
                self.isStopped = true
            }
            if self.isStopped || self.stillFrames >= 2 || self.stitcher.isFull || self.frames >= Self.maximumFrames {
                self.finish()
                return
            }
            self.scroll()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) { [weak self] in
                self?.captureNext()
            }
        }
    }

    private func turnRound() {
        direction = -direction
        hasTurnedRound = true
        stillFrames = 0
    }

    /// The step that would have moved the page by about half a frame, judging by the last one.
    /// Half leaves a wide margin: a step that moves the page by almost a whole frame leaves too
    /// little in common with the frame before, and the place in the page is lost.
    static func adjustedLines(_ lines: Int32, moved rows: Int, frameHeight: Int) -> Int32 {
        guard rows > 0, frameHeight > 0 else { return lines }
        let wanted = Double(lines) * 0.5 * Double(frameHeight) / Double(rows)
        return Int32(min(max(wanted.rounded(), 1), 40))
    }

    /// Scrolls the page under the middle of the region by a few lines. The pointer visits the
    /// region for a moment, because a scroll goes to the window under it; it travels there as a
    /// real pointer movement, since a silent jump does not always tell the system where it is.
    ///
    /// Line steps, not pixel ones: apps ignore a synthetic pixel scroll that carries no gesture
    /// phase (tried with TextEdit: nothing moved).
    private func scroll() {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pointer = CGEvent(source: nil)?.location
        Self.movePointer(to: center)
        let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: direction * linesPerStep,
            wheel2: 0, wheel3: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            event?.post(tap: .cghidEventTap)
        }
        if let pointer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Self.movePointer(to: pointer)
            }
        }
    }

    private static func movePointer(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func finish() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
        completion(FrameRows.stitch(parts))
    }
}
