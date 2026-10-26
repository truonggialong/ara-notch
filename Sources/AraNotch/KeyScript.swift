import AppKit
import ClipboardFeature

/// Diagnostics: feeds scripted key presses to the clipboard panel.
///
/// The events are posted to this app's own event queue, so they travel the same path as real
/// key presses but never leave the app or reach any other application.
///
/// Script: comma-separated steps. `down`, `up`, `left`, `right`, `return`, `cmd-return`,
/// `cmd-delete`, `esc`, `cmd-1` … `cmd-9`, or `text:<string>` to set the search text.
@MainActor
enum KeyScript {
    private static let startDelay: TimeInterval = 0.6
    private static let stepInterval: TimeInterval = 0.15
    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// Schedules the steps and returns the time, from now, at which the last one runs.
    static func run(_ script: String, clipboard: ClipboardController) -> TimeInterval {
        let steps = script.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + Double(index) * stepInterval) {
                perform(step, clipboard: clipboard)
            }
        }
        return startDelay + Double(max(steps.count - 1, 0)) * stepInterval
    }

    private static func perform(_ step: String, clipboard: ClipboardController) {
        if step.hasPrefix("text:") {
            clipboard.setSearchText(String(step.dropFirst("text:".count)))
            return
        }
        guard let (keyCode, flags) = key(for: step), let windowNumber = clipboard.panelWindowNumber,
              let event = NSEvent.keyEvent(
                  with: .keyDown, location: .zero, modifierFlags: flags,
                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                  context: nil, characters: "", charactersIgnoringModifiers: "",
                  isARepeat: false, keyCode: keyCode)
        else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private static func key(for step: String) -> (UInt16, NSEvent.ModifierFlags)? {
        switch step {
        case "left": return (123, [])
        case "right": return (124, [])
        case "down": return (125, [])
        case "up": return (126, [])
        case "return": return (36, [])
        case "cmd-return": return (36, .command)
        case "cmd-delete": return (51, .command)
        case "esc": return (53, [])
        default:
            guard step.hasPrefix("cmd-"), let digit = Int(step.dropFirst(4)), (1...9).contains(digit) else {
                return nil
            }
            return (digitKeyCodes[digit - 1], .command)
        }
    }
}
