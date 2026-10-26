import AppKit
import ApplicationServices

/// Sends ⌘V to the app the user is working in. macOS only allows this with Accessibility permission.
@MainActor
enum Paster {
    private static let vKeyCode: CGKeyCode = 9

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open the Accessibility settings.
    static func requestTrust() {
        let promptKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func pasteIntoFrontmostApp() {
        guard isTrusted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: isDown)
            event?.flags = .maskCommand
            // Marked as this app's own, so the copy stack does not count it as a paste by the user.
            event?.setIntegerValueField(.eventSourceUserData, value: PasteKeyTap.ownEventMarker)
            event?.post(tap: .cghidEventTap)
        }
    }
}
