import AppKit
import Carbon.HIToolbox
import Combine
import NotchCore
import SwiftUI

/// The app's global shortcuts in one place: which keys they are (the user can change or remove
/// each one), what they do, and whether the system accepted them.
@MainActor
public final class ShortcutCenter: ObservableObject {
    private let store: ShortcutStore
    private let hotKeys = GlobalHotKeys()
    private var handlers: [ShortcutAction: () -> Void] = [:]
    /// The number rows features declared, in the order they did, and what their digits do.
    private var numberRows: [NumberRow] = []
    private var numberRowHandlers: [NumberRow: (Int) -> Void] = [:]
    /// Actions switched off by their own feature's setting; they keep their keys but are not registered.
    private var disabled: Set<ShortcutAction> = []

    /// The current shortcut of each action that has one.
    @Published public private(set) var combos: [ShortcutAction: KeyCombo] = [:]
    /// Shortcuts the system refused, usually because another app holds them.
    @Published public private(set) var refused: Set<ShortcutAction> = []
    /// The modifiers of each declared number row that is on.
    @Published public private(set) var numberRowModifiers: [NumberRow: KeyComboModifiers] = [:]
    /// Number rows of which the system refused some keys.
    @Published public private(set) var refusedNumberRows: Set<NumberRow> = []

    public init(store: ShortcutStore) {
        self.store = store
        reload()
    }

    /// What pressing the action's shortcut does.
    public func setHandler(_ action: ShortcutAction, _ handler: @escaping () -> Void) {
        handlers[action] = handler
        register()
    }

    /// Declares a number row and what its digits do, given the number 1…9.
    public func setNumberRow(_ row: NumberRow, handler: @escaping (Int) -> Void) {
        if !numberRows.contains(row) {
            numberRows.append(row)
        }
        numberRowHandlers[row] = handler
        reload()
    }

    /// Lets a feature's own switch turn its shortcut off without forgetting the keys.
    public func setEnabled(_ isEnabled: Bool, for action: ShortcutAction) {
        if isEnabled {
            disabled.remove(action)
        } else {
            disabled.insert(action)
        }
        register()
    }

    /// The action's keys for display, or a word for "none".
    public func label(for action: ShortcutAction) -> String {
        KeyLabel.text(for: combos[action]) ?? L10n.string("settings.shortcuts.none")
    }

    public func isRefused(_ action: ShortcutAction) -> Bool {
        refused.contains(action)
    }

    /// The action that already uses this combo, so the settings can say so instead of taking it.
    public func conflict(for combo: KeyCombo, assigning action: ShortcutAction) -> ShortcutAction? {
        store.action(using: combo, otherThan: action)
    }

    /// The number row that already uses this combo, if any.
    public func numberRow(using combo: KeyCombo) -> NumberRow? {
        numberRows.first { store.combos(for: $0).contains(combo) }
    }

    public func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        store.set(combo, for: action)
        reload()
    }

    public func reset(_ action: ShortcutAction) {
        store.reset(action)
        reload()
    }

    /// Whether the action's shortcut is not the one the app ships with.
    public func differsFromDefault(_ action: ShortcutAction) -> Bool {
        store.differsFromDefault(action)
    }

    /// Sets the modifiers of a number row; nil turns it off. Modifiers another row has are refused.
    public func setModifiers(_ modifiers: KeyComboModifiers?, for row: NumberRow) {
        store.setModifiers(modifiers, for: row, others: numberRows)
        reload()
    }

    /// While a shortcut is being recorded none is registered, so the keys reach the recorder.
    public var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            register()
        }
    }

    private func reload() {
        var combos: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            combos[action] = store.combo(for: action)
        }
        self.combos = combos
        var modifiers: [NumberRow: KeyComboModifiers] = [:]
        for row in numberRows {
            modifiers[row] = store.modifiers(for: row)
        }
        numberRowModifiers = modifiers
        register()
    }

    private func register() {
        hotKeys.unregisterAll()
        var refused: Set<ShortcutAction> = []
        var refusedNumberRows: Set<NumberRow> = []
        defer {
            self.refused = refused
            self.refusedNumberRows = refusedNumberRows
        }
        guard !isRecording else { return }

        for (action, combo) in combos {
            guard !disabled.contains(action), let handler = handlers[action] else { continue }
            if !hotKeys.register(keyCode: combo.keyCode, modifiers: Self.modifiers(combo.modifiers), action: handler) {
                refused.insert(action)
            }
        }
        for row in numberRows {
            guard let handler = numberRowHandlers[row] else { continue }
            for (index, combo) in store.combos(for: row).enumerated() {
                let registered = hotKeys.register(
                    keyCode: combo.keyCode, modifiers: Self.modifiers(combo.modifiers)
                ) { handler(index + 1) }
                if !registered {
                    refusedNumberRows.insert(row)
                }
            }
        }
    }

    private static func modifiers(_ modifiers: KeyComboModifiers) -> GlobalHotKeys.Modifiers {
        GlobalHotKeys.Modifiers(rawValue: modifiers.rawValue)
    }
}

/// Names keys for display, in the user's keyboard layout.
@MainActor
public enum KeyLabel {
    /// Keys that print nothing, or whose name is clearer than what they print.
    private static let named: [UInt32: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// "⌃⌥C", or nil for no shortcut.
    public static func text(for combo: KeyCombo?) -> String? {
        combo.map { $0.modifierSymbols + key($0.keyCode) }
    }

    /// The key's name: what it types in the current layout, in capitals, or a symbol. Never
    /// fails: a key the layout cannot name is shown by its number.
    public static func key(_ keyCode: UInt32) -> String {
        if let name = named[keyCode] { return name }
        if let typed = character(for: keyCode), !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return typed.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// What the key types with no modifier held, from the current keyboard layout.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, UInt16(truncatingIfNeeded: keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

/// A field that shows a shortcut and records a new one: click it, then press the keys.
/// ⌫ removes the shortcut, ⎋ leaves it as it was.
struct ShortcutRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    /// Called with the new combo, or nil when the user removed the shortcut.
    let onChange: (KeyCombo?) -> Void
    let onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.onChange = onChange
        field.onRecording = onRecording
        field.combo = combo
        return field
    }

    func updateNSView(_ field: RecorderField, context: Context) {
        field.onChange = onChange
        field.onRecording = onRecording
        field.combo = combo
    }

    final class RecorderField: NSView {
        var onChange: ((KeyCombo?) -> Void)?
        var onRecording: ((Bool) -> Void)?
        var combo: KeyCombo? {
            didSet { needsDisplay = true }
        }

        private var isRecording = false {
            didSet {
                guard isRecording != oldValue else { return }
                needsDisplay = true
                onRecording?(isRecording)
            }
        }

        override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: KeyComboModifiers = []
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            let keyCode = UInt32(event.keyCode)

            if modifiers.isEmpty, keyCode == 53 {
                isRecording = false
                return
            }
            if modifiers.isEmpty, keyCode == 51 || keyCode == 117 {
                isRecording = false
                onChange?(nil)
                return
            }
            let candidate = KeyCombo(keyCode: keyCode, modifiers: modifiers)
            guard candidate.isValid else {
                NSSound.beep()
                return
            }
            isRecording = false
            onChange?(candidate)
        }

        /// ⌘-combinations would otherwise go to the menu bar instead of `keyDown`.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.quaternaryLabelColor).setFill()
            box.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            box.stroke()

            let text: String
            let color: NSColor
            if isRecording {
                text = L10n.string("settings.shortcuts.recording")
                color = .labelColor
            } else if let label = KeyLabel.text(for: combo) {
                text = label
                color = .labelColor
            } else {
                // "Off" reads as a state, not as a field that cannot be used.
                text = L10n.string("settings.shortcuts.none")
                color = .secondaryLabelColor
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .regular : .medium), .foregroundColor: color,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes)
        }
    }
}

/// One tool in Settings: its name and a short line under it, and its shortcut field. The field
/// says "Off" for a tool that is off; giving it keys turns the tool on and ⌫ turns it off, so a
/// tool never shows keys that do nothing. A shortcut that could not be set says why in place of
/// the line.
public struct ShortcutRow: View {
    @ObservedObject var center: ShortcutCenter
    let action: ShortcutAction
    let titleKey: String
    let noteKey: String?
    /// Whether the tool is on, for a tool that can be off while it keeps its keys.
    let isOn: Binding<Bool>?
    @StateObject private var feedback = ShortcutFeedback()

    public init(
        center: ShortcutCenter, action: ShortcutAction, titleKey: String, noteKey: String? = nil,
        isOn: Binding<Bool>? = nil
    ) {
        self.center = center
        self.action = action
        self.titleKey = titleKey
        self.noteKey = noteKey
        self.isOn = isOn
    }

    private var isOff: Bool { isOn?.wrappedValue == false }

    public var body: some View {
        // Laid out by hand: a shortcut field alone was pushed under the title by the form.
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string(titleKey))
                if let message = feedback.messages[action] {
                    Text(message).font(.caption).foregroundStyle(AraPalette.warning)
                } else if !isOff, center.isRefused(action) {
                    Text(L10n.string("settings.shortcuts.refused")).font(.caption).foregroundStyle(AraPalette.warning)
                } else if let noteKey {
                    AraSettingsNote(L10n.string(noteKey))
                }
            }
            Spacer(minLength: 8)
            // Only where there is a default to go back to.
            if !isOff, center.differsFromDefault(action) {
                Button {
                    restoreDefault()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("settings.shortcuts.restore"))
                .accessibilityLabel(L10n.string("settings.shortcuts.restore"))
            }
            ShortcutRecorder(combo: isOff ? nil : center.combos[action]) { combo in
                assign(combo)
            } onRecording: { isRecording in
                center.isRecording = isRecording
            }
            .frame(width: 130, height: 24)
        }
    }

    /// Back to the shortcut the app ships with, unless another action took those keys meanwhile.
    private func restoreDefault() {
        feedback.messages[action] = nil
        if let combo = action.defaultCombo, let other = center.conflict(for: combo, assigning: action) {
            feedback.messages[action] = String(
                format: L10n.string("settings.shortcuts.conflict"), KeyLabel.text(for: combo) ?? "",
                L10n.string("shortcut.\(other.rawValue)"))
            return
        }
        center.reset(action)
    }

    private func assign(_ combo: KeyCombo?) {
        feedback.messages[action] = nil
        guard let combo else {
            // A tool that can be off keeps its keys for when it is turned on again.
            if let isOn {
                isOn.wrappedValue = false
            } else {
                center.set(nil, for: action)
            }
            return
        }
        if let other = center.conflict(for: combo, assigning: action) {
            feedback.messages[action] = String(
                format: L10n.string("settings.shortcuts.conflict"), KeyLabel.text(for: combo) ?? "",
                L10n.string("shortcut.\(other.rawValue)"))
            return
        }
        if let row = center.numberRow(using: combo) {
            feedback.messages[action] = String(
                format: L10n.string("settings.shortcuts.conflict"), KeyLabel.text(for: combo) ?? "",
                L10n.string(row.titleKey))
            return
        }
        center.set(combo, for: action)
        isOn?.wrappedValue = true
    }
}

/// The modifiers held with 1 to 9 for a number row, or off. The modifiers the other rows
/// use are left out.
public struct ShortcutNumberRowPicker: View {
    @ObservedObject var center: ShortcutCenter
    let row: NumberRow

    public init(center: ShortcutCenter, row: NumberRow) {
        self.center = center
        self.row = row
    }

    public var body: some View {
        let selected = center.numberRowModifiers[row]
        let taken = Set(center.numberRowModifiers.filter { $0.key != row }.map(\.value.rawValue))
        Picker(selection: Binding(
            get: { selected?.rawValue ?? 0 },
            set: { value in center.setModifiers(value == 0 ? nil : KeyComboModifiers(rawValue: value), for: row) }
        )) {
            Text(L10n.string("settings.off")).tag(0)
            ForEach(Self.choices.filter { !taken.contains($0.rawValue) }, id: \.rawValue) { modifiers in
                Text("\(modifiers.symbols)1 … \(modifiers.symbols)9").tag(modifiers.rawValue)
            }
        } label: {
            Text(L10n.string(row.titleKey))
            if center.refusedNumberRows.contains(row) {
                Text(L10n.string("settings.shortcuts.numberRow.refused")).font(.caption).foregroundStyle(AraPalette.warning)
            } else {
                AraSettingsNote(L10n.string(row.noteKey))
            }
        }
    }

    /// Without ⌃ alone and ⌥ alone: with a digit, macOS uses the first to switch desktops and
    /// the second types a character.
    private static let choices: [KeyComboModifiers] = [
        [.control, .option], [.control, .shift], [.control, .command], [.option, .command],
        [.control, .option, .command],
    ]
}

/// Messages shown under a shortcut that could not be assigned.
@MainActor
final class ShortcutFeedback: ObservableObject {
    @Published var messages: [ShortcutAction: String] = [:]
}
