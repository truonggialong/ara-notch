import AppKit

/// Gives a text field keyboard focus, retrying briefly while SwiftUI is still putting it on screen.
@MainActor
enum FieldFocus {
    private static let retryDelay: TimeInterval = 0.05

    static func focus(_ field: NSTextField, attempts: Int = 8) {
        if let window = field.window {
            // First responder alone is not enough: keystrokes go to the key window, and the
            // notch panel only becomes key by itself when a text field in it is clicked.
            window.makeKey()
            if window.makeFirstResponder(field) { return }
        }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            focus(field, attempts: attempts - 1)
        }
    }
}
