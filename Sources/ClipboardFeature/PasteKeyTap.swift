import AppKit
import ApplicationServices

/// Notices every ⌘V the user presses, in any app, just before the app receives it.
/// Needs Accessibility permission; without it `start()` returns false.
@MainActor
final class PasteKeyTap {
    /// Marks key events this app posts itself, so its own pastes are not taken for the user's.
    static let ownEventMarker: Int64 = 0x4152_4E50 /* 'ARNP' */
    private static let vKeyCode: Int64 = 9

    /// Called on the main thread, before the paste reaches the app in front.
    var onPaste: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<PasteKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap is installed on the main run loop, so this runs on the main thread.
                MainActor.assumeIsolated { owner.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system switches a tap off when it is slow; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == Self.vKeyCode,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.getIntegerValueField(.eventSourceUserData) != Self.ownEventMarker
        else { return }
        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard flags == .maskCommand else { return }
        onPaste?()
    }
}
