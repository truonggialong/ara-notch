import AppKit
import ApplicationServices
import WindowsCore

/// Moves and resizes the front window of whatever app the user is working in, through the
/// Accessibility interface. macOS allows this only with Accessibility permission.
@MainActor
enum WindowMover {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Snaps the front window to a zone of the display it is mostly on.
    /// Returns false when there is no permission, no window, or the app refuses.
    /// - Parameter screen: the display to snap on; nil picks the one the window is mostly on.
    @discardableResult
    static func snap(to zone: SnapZone, on screen: NSScreen? = nil) -> Bool {
        guard isTrusted, let window = frontWindow(), let current = frame(of: window),
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return false }

        let screens = NSScreen.screens
        let appKitFrame = SnapGeometry.frame(topLeft: current.origin, size: current.size, primaryScreenHeight: primaryHeight)
        guard let chosen = screen
            ?? SnapGeometry.displayIndex(for: appKitFrame, among: screens.map(\.frame)).map({ screens[$0] })
        else { return false }

        let target = zone.frame(in: chosen.visibleFrame)
        let origin = SnapGeometry.topLeftOrigin(of: target, primaryScreenHeight: primaryHeight)
        // Size first, then position, then size again: a window pressed against a display edge
        // may refuse to grow until it has been moved.
        let sized = setSize(target.size, of: window)
        let moved = setPosition(origin, of: window)
        _ = setSize(target.size, of: window)
        return sized && moved
    }

    /// Where the front window's top-left corner is, in the Accessibility interface's coordinates.
    static func frontWindowOrigin() -> CGPoint? {
        guard isTrusted, let window = frontWindow() else { return nil }
        return frame(of: window)?.origin
    }

    private static func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// The window's frame with a top-left origin, as the Accessibility interface reports it.
    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func setPosition(_ position: CGPoint, of window: AXUIElement) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }
}
