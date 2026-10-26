import AppKit
import NotchShell
import SwiftUI

/// A plain text field that can be told to take keyboard focus, which SwiftUI's `TextField`
/// can only do through `@FocusState` (unavailable without Xcode's macro plugin).
struct PanelSearchField: NSViewRepresentable {
    let text: String
    let placeholder: String
    /// Changing this value makes the field the first responder.
    let focusToken: Int
    var fontSize: CGFloat = 15
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = AraPalette.nsFont(size: fontSize)
        field.textColor = AraPalette.nsInk
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: AraPalette.nsPlaceholder,
                .font: AraPalette.nsFont(size: fontSize),
            ])
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.onChange = onChange
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            // Deferred: the field may not be in its window yet during this update pass.
            DispatchQueue.main.async {
                FieldFocus.focus(field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onChange: (String) -> Void
        var focusToken = -1

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}
