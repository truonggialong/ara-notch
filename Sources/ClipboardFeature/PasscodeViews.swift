import AppKit
import ClipboardCore
import NotchShell
import SwiftUI

/// A text field that hides what is typed and can be told to take keyboard focus.
struct SecureEntryField: NSViewRepresentable {
    let text: String
    let placeholder: String
    /// Changing this value makes the field the first responder; nil never grabs focus.
    let focusToken: Int?
    let onChange: (String) -> Void
    /// Return in the field; nil where something else already handles the key (the notch).
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = AraPalette.nsFont(size: 12 * context.environment.araScale)
        field.textColor = AraPalette.nsInk
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: AraPalette.nsPlaceholder, .font: AraPalette.nsFont(size: 12 * context.environment.araScale)])
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text {
            field.stringValue = text
        }
        if let focusToken, context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                FieldFocus.focus(field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onChange: (String) -> Void
        var onSubmit: (() -> Void)?
        var focusToken = -1

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), let onSubmit else { return false }
            onSubmit()
            return true
        }
    }
}

/// Replaces the top row while the vault passcode is being asked for or chosen.
struct PasscodeRowView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: ClipboardViewModel
    let prompt: ClipboardViewModel.PasscodePrompt
    /// Return submits from the field itself: in a window, where the notch's keys do not reach.
    var submitsOnReturn = false

    var body: some View {
        HStack(spacing: 6 * ui) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11 * ui))
                .foregroundStyle(AraPalette.label)
                .frame(width: 22 * ui)

            field(
                text: prompt.passcode, placeholderKey: "clipboard.vault.passcode.placeholder",
                focusToken: model.passcodeFocusToken
            ) { model.passcodePrompt?.passcode = $0 }
            if prompt.isCreating {
                field(
                    text: prompt.confirmation, placeholderKey: "clipboard.vault.confirm.placeholder",
                    focusToken: nil
                ) { model.passcodePrompt?.confirmation = $0 }
            }

            if let errorKey = prompt.errorKey {
                Text(L10n.string(errorKey))
                    .font(.system(size: 10 * ui))
                    .foregroundStyle(AraPalette.danger)
                    .lineLimit(1)
                    .fixedSize()
            }

            if model.canUseTouchID, !prompt.isCreating {
                AraIconButton(.touchID, size: .small, help: L10n.string("clipboard.vault.touchID")) {
                    model.onUnlockWithTouchID?()
                }
            }
            AraIconButton(
                prompt.isCreating ? .confirm : .unlocked, look: .accent, size: .small,
                help: L10n.string(prompt.isCreating ? "clipboard.vault.create" : "clipboard.vault.unlock")
            ) {
                model.onSubmitPasscode?()
            }
            AraIconButton(.close, size: .small, help: L10n.string("settings.cancel")) { model.onCancelPasscode?() }
        }
    }

    private func field(
        text: String, placeholderKey: String, focusToken: Int?, onChange: @escaping (String) -> Void
    ) -> some View {
        SecureEntryField(
            text: text, placeholder: L10n.string(placeholderKey), focusToken: focusToken, onChange: onChange,
            onSubmit: submitsOnReturn ? { model.onSubmitPasscode?() } : nil)
            .padding(.horizontal, 8 * ui)
            .frame(height: 24 * ui)
            .araSurface(Capsule())
    }
}
