import AppKit
import Carbon.HIToolbox

/// Global shortcuts that work in every app. Carbon hot keys need no system permission.
/// Each instance only reacts to the shortcuts it registered itself.
@MainActor
public final class GlobalHotKeys {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    private static var nextSignature: OSType = 0x4152_4E30 /* 'ARN0' */

    /// Tells this instance's shortcuts apart from those of other instances in the app.
    private let signature: OSType
    private var actions: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    public init() {
        signature = Self.nextSignature
        Self.nextSignature += 1
    }

    /// Registers a shortcut by virtual key code. Returns false when the system refuses it, for
    /// example because another app already owns it.
    @discardableResult
    public func register(keyCode: UInt32, modifiers: Modifiers, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        var carbonModifiers = 0
        if modifiers.contains(.control) { carbonModifiers |= controlKey }
        if modifiers.contains(.option) { carbonModifiers |= optionKey }
        if modifiers.contains(.shift) { carbonModifiers |= shiftKey }
        if modifiers.contains(.command) { carbonModifiers |= cmdKey }

        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, UInt32(carbonModifiers), EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references.append(reference)
        actions[id] = action
        return true
    }

    public func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references = []
        actions = [:]
    }

    private func fire(signature: OSType, id: UInt32) -> Bool {
        guard signature == self.signature, let action = actions[id] else { return false }
        action()
        return true
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                let (signature, id) = (identifier.signature, identifier.id)
                // Carbon delivers hot key events on the main thread. A shortcut of another
                // registrar is passed on, so its own handler gets it.
                let handled = MainActor.assumeIsolated { hotKeys.fire(signature: signature, id: id) }
                return handled ? noErr : OSStatus(eventNotHandledErr)
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
