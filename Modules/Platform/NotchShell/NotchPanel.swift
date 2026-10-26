import AppKit
import SwiftUI

/// Transparent window that sits above the menu bar. It never activates the app, and takes
/// keyboard focus only when a text field inside it is clicked.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // While the notch is closed the window must not block the menu bar underneath it.
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        // The notch is the night card whatever the appearance of the rest of the app, and
        // so are the menus and text fields inside it.
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts the notch. AppKit sets the pointer again on every tracking area the pointer crosses
/// and on every change of page, though the notch only ever shows the arrow; with a pointer of a
/// custom size or colour (Accessibility settings) macOS draws its image anew each time, some
/// 50 ms on the main thread, and hovering and changing pages stutter. The arrow is set once
/// when the pointer comes in, and again only when something else (a text field's I-beam) has
/// replaced it.
class NotchHostingView<Content: View>: NSHostingView<Content> {
    private var hasSetArrow = false
    private var presence: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let presence {
            removeTrackingArea(presence)
        }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        presence = area
    }

    // The presence area is this view's own; SwiftUI's hover never hears of it.
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === presence else { return super.mouseEntered(with: event) }
        hasSetArrow = false
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === presence else { return super.mouseExited(with: event) }
        hasSetArrow = false
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !hasSetArrow || NSCursor.current != NSCursor.arrow else { return }
        super.cursorUpdate(with: event)
        hasSetArrow = NSCursor.current == NSCursor.arrow
    }
}

/// Lets controls react to the first click even though the panel is usually not the key window.
final class FirstMouseHostingView<Content: View>: NotchHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// An invisible window over what shows on the closed notch (a sign, the track beside it) that
/// takes the clicks there, so that they do not also land in the app underneath. It never
/// becomes key and never activates the app; the notch reads the clicks from its event monitor.
final class NotchClickCatcher: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Said outright: a clear window would otherwise let clicks through where it is clear.
        ignoresMouseEvents = false
        contentView = ClickCatcherView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClickCatcherView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The click is taken and nothing more: the notch has already seen it.
    override func mouseDown(with event: NSEvent) {}
}
