import Foundation

/// The modifier keys of a shortcut.
public struct KeyComboModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = KeyComboModifiers(rawValue: 1)
    public static let option = KeyComboModifiers(rawValue: 2)
    public static let shift = KeyComboModifiers(rawValue: 4)
    public static let command = KeyComboModifiers(rawValue: 8)

    /// ⌃⌥⇧⌘, the order macOS menus use.
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

/// A key with its modifiers: a global shortcut. The key is a virtual key code, the position
/// of a key on the keyboard, so a shortcut is the same physical keys on every keyboard layout.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyComboModifiers

    public init(keyCode: UInt32, modifiers: KeyComboModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The function keys F1…F20, which may be shortcuts with no modifier at all.
    static let functionKeys: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// A shortcut must not take a key people type with: it needs ⌘, ⌃ or ⌥, or be a function key.
    public var isValid: Bool {
        Self.functionKeys.contains(keyCode) || !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    public var modifierSymbols: String { modifiers.symbols }

    /// "modifiers:keyCode", for the settings file.
    public var storage: String { "\(modifiers.rawValue):\(keyCode)" }

    public init?(storage: String) {
        let parts = storage.split(separator: ":")
        guard parts.count == 2, let modifiers = Int(parts[0]), let keyCode = UInt32(parts[1]),
              (0...15).contains(modifiers)
        else { return nil }
        self.init(keyCode: keyCode, modifiers: KeyComboModifiers(rawValue: modifiers))
    }
}

/// What a global shortcut can do.
public enum ShortcutAction: String, CaseIterable, Sendable {
    case clipboardPanel
    case translate
    case captureRegion
    case captureScrolling
    case captureText
    case pickColor
    case openNotch
    case hideNotch
    case newNote

    /// The shortcut the action has until the user changes it; nil for none.
    public var defaultCombo: KeyCombo? {
        switch self {
        case .clipboardPanel: KeyCombo(keyCode: 8, modifiers: [.command, .shift])
        case .translate: KeyCombo(keyCode: 5, modifiers: [.command, .shift])
        case .captureRegion: KeyCombo(keyCode: 19, modifiers: [.command, .shift])
        case .captureScrolling, .captureText, .pickColor, .openNotch, .hideNotch, .newNote: nil
        }
    }
}

/// Reads and writes the user's shortcuts.
public struct ShortcutStore {
    /// Top-row digits 1…9 in order; their key codes are not consecutive.
    public static let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func key(_ action: ShortcutAction) -> String {
        "shortcut.\(action.rawValue)"
    }

    /// The action's shortcut: the user's, or the default when they never touched it.
    public func combo(for action: ShortcutAction) -> KeyCombo? {
        // An empty string is a shortcut the user removed; that is not "never set".
        guard let stored = defaults.string(forKey: key(action)) else { return action.defaultCombo }
        return KeyCombo(storage: stored)
    }

    /// Sets the action's shortcut; nil removes it. A combo that is not valid is ignored.
    public func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        guard let combo else {
            defaults.set("", forKey: key(action))
            return
        }
        guard combo.isValid else { return }
        defaults.set(combo.storage, forKey: key(action))
    }

    /// Back to the action's default shortcut.
    public func reset(_ action: ShortcutAction) {
        defaults.removeObject(forKey: key(action))
    }

    /// True when the action's shortcut is not the one the app ships with, so there is a default to go back to.
    public func differsFromDefault(_ action: ShortcutAction) -> Bool {
        combo(for: action) != action.defaultCombo
    }

    /// Another action that already has this shortcut, if any.
    public func action(using combo: KeyCombo, otherThan action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && self.combo(for: $0) == combo }
    }

    /// The modifiers the row's digits are held with; nil for off.
    public func modifiers(for row: NumberRow) -> KeyComboModifiers? {
        guard let raw = defaults.object(forKey: row.storageKey) as? Int, (1...15).contains(raw) else { return nil }
        let modifiers = KeyComboModifiers(rawValue: raw)
        return modifiers.isDisjoint(with: [.command, .control, .option]) ? nil : modifiers
    }

    /// Stores a row's modifiers; nil turns the row off. Refused when they are only Shift, or
    /// when one of the `others` rows already has them: rows cannot share their keys.
    public func setModifiers(_ modifiers: KeyComboModifiers?, for row: NumberRow, others: [NumberRow]) {
        guard let modifiers else {
            defaults.removeObject(forKey: row.storageKey)
            return
        }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]),
              !others.contains(where: { $0 != row && self.modifiers(for: $0) == modifiers })
        else { return }
        defaults.set(modifiers.rawValue, forKey: row.storageKey)
    }

    /// The row's nine shortcuts, for the digits 1…9 in order; empty when the row is off.
    public func combos(for row: NumberRow) -> [KeyCombo] {
        guard let modifiers = modifiers(for: row) else { return [] }
        return Self.digitKeyCodes.map { KeyCombo(keyCode: $0, modifiers: modifiers) }
    }
}

/// A row of nine global shortcuts: modifiers the user chooses, held with the digits 1…9. A
/// feature declares its rows and what the digits do; the rows cannot share their modifiers.
public struct NumberRow: Hashable, Sendable {
    /// Where the chosen modifiers are kept.
    public let storageKey: String
    /// The row's name in Settings and in a message about keys it already uses.
    public let titleKey: String
    /// The line under the row's name in Settings.
    public let noteKey: String

    public init(storageKey: String, titleKey: String, noteKey: String) {
        self.storageKey = storageKey
        self.titleKey = titleKey
        self.noteKey = noteKey
    }
}
