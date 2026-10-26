/// Modifier keys held during a key press, independent of AppKit.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

public enum ClipPanelCommand: Equatable, Sendable {
    case moveNext
    case movePrevious
    /// Paste the selected clip into the app the user is working in.
    case paste
    /// Paste the selected clip as plain text, without its formatting.
    case pastePlain
    /// Put the selected clip on the pasteboard without pasting.
    case copy
    case delete
    /// Paste the clip at this zero-based position.
    case pasteIndex(Int)
    case clearSearch
    case close
    /// Take back the deletion made a moment ago.
    case undo
    /// Show the selected clip in full, or put that view away.
    case preview
    /// Not a list command: let the search field handle the key.
    case passThrough
}

/// Direction in which the list of clips runs.
public enum ClipListAxis: Sendable {
    /// The floating panel: ↑ and ↓ move the selection.
    case vertical
    /// The notch row: ← and → move the selection, but only while the search field is empty,
    /// because otherwise they move the caret.
    case horizontal
}

/// Turns a key press in a clipboard list into a command.
public enum ClipPanelKeyMap {
    private enum KeyCode {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let z: UInt16 = 6
        static let space: UInt16 = 49
        /// Top-row digits 1…9 in order; their key codes are not consecutive.
        static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    public static func command(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        axis: ClipListAxis,
        searchIsEmpty: Bool
    ) -> ClipPanelCommand {
        switch keyCode {
        case KeyCode.down, KeyCode.up:
            guard modifiers.isEmpty, axis == .vertical else { return .passThrough }
            return keyCode == KeyCode.down ? .moveNext : .movePrevious
        case KeyCode.right, KeyCode.left:
            guard modifiers.isEmpty, axis == .horizontal, searchIsEmpty else { return .passThrough }
            return keyCode == KeyCode.right ? .moveNext : .movePrevious
        case KeyCode.returnKey, KeyCode.enter:
            if modifiers.isEmpty { return .paste }
            if modifiers == .option { return .pastePlain }
            return modifiers == .command ? .copy : .passThrough
        case KeyCode.delete:
            return modifiers == .command ? .delete : .passThrough
        case KeyCode.escape:
            return searchIsEmpty ? .close : .clearSearch
        case KeyCode.z:
            return modifiers == .command ? .undo : .passThrough
        case KeyCode.space:
            // A space is a letter of the search once something is typed.
            return modifiers.isEmpty && searchIsEmpty ? .preview : .passThrough
        default:
            if modifiers == .command, let index = KeyCode.digits.firstIndex(of: keyCode) {
                return .pasteIndex(index)
            }
            return .passThrough
        }
    }
}
