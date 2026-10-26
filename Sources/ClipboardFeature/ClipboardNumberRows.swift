import NotchCore

/// The clipboard's two rows of 1…9 shortcuts. Their modifiers stay under the keys they had
/// when the shell kept them.
public enum ClipboardNumberRows {
    /// Pastes clip N of the chosen board.
    public static let pinned = NumberRow(
        storageKey: "shortcut.quickPasteModifiers", titleKey: "settings.shortcuts.quickPaste",
        noteKey: "settings.shortcuts.quickPaste.note")
    /// Pastes the Nth newest clip of the history.
    public static let recent = NumberRow(
        storageKey: "shortcut.recentPasteModifiers", titleKey: "settings.shortcuts.recentPaste",
        noteKey: "settings.shortcuts.recentPaste.note")
    /// In the order Settings lists them.
    public static let all = [recent, pinned]
}
