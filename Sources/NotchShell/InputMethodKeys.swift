import AppKit

public extension NSEvent {
    /// The key is for an input method that is composing a word in the focused text field of
    /// the key's window. Vietnamese Telex and VNI underline the syllable being built until it is
    /// committed, as Japanese and Chinese do; Return, Escape, Tab, the arrows and Delete are the
    /// input method's then. A key monitor that took them would cut the word short or lose it.
    @MainActor
    var isForInputMethod: Bool {
        guard let editor = window?.firstResponder as? NSTextView else { return false }
        return editor.hasMarkedText()
    }
}
