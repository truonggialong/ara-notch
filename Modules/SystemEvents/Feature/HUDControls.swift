import AppKit
import ApplicationServices
import CoreAudio
import SystemEventsCore

/// Catches the volume and brightness keys before the system acts on them, so the notch can
/// show the change instead of the system's own display. Needs Accessibility permission.
@MainActor
final class MediaKeyTap {
    /// `NSEvent.EventType.systemDefined`, and the subtype that carries the special keys.
    private static let systemDefined: UInt32 = 14
    private static let specialKeySubtype: Int16 = 8

    /// Called for each press of a handled key. Return true when the key was dealt with; the
    /// system then never sees it. Return false to let it through.
    var onKey: ((MediaKeyEvent, _ fine: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << Self.systemDefined),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap is installed on the main run loop, so this runs on the main thread.
                let consumed = MainActor.assumeIsolated { owner.handle(type: type, event: event) }
                return consumed ? nil : Unmanaged.passUnretained(event)
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

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }
        guard type.rawValue == Self.systemDefined, let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.specialKeySubtype,
              let key = MediaKeyEvent(data1: nsEvent.data1)
        else { return false }
        // The release is swallowed together with its press, or the system would see half a key.
        guard key.isDown else { return onKey != nil && handlesReleases }
        let flags = nsEvent.modifierFlags
        let handled = onKey?(key, flags.contains(.option) && flags.contains(.shift)) ?? false
        handlesReleases = handled
        return handled
    }

    /// Whether the last press was dealt with here.
    private var handlesReleases = false
}

/// The volume of the device sound goes to, through Core Audio.
@MainActor
enum VolumeControl {
    /// 'vmvc': the device's overall volume, as the system's own slider sets it.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    private static func device() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    /// 0…1, or nil when the device has no volume the system can set (some displays, some USB devices).
    static var level: Float? {
        get {
            guard let device = device() else { return nil }
            var volumeAddress = address(virtualMainVolume)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        set {
            guard let newValue, let device = device() else { return }
            var volumeAddress = address(virtualMainVolume)
            var value = Float32(min(max(newValue, 0), 1))
            _ = AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static var isMuted: Bool {
        get {
            guard let device = device() else { return false }
            var muteAddress = address(kAudioDevicePropertyMute)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr else { return false }
            return value != 0
        }
        set {
            guard let device = device() else { return }
            var muteAddress = address(kAudioDevicePropertyMute)
            var value: UInt32 = newValue ? 1 : 0
            _ = AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

/// The brightness of the built-in display. macOS has no public interface for it; this uses
/// the DisplayServices framework the system's own controls use, and reports nil when that
/// is missing or the display cannot be dimmed, in which case the keys are left to the system.
@MainActor
enum BrightnessControl {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: Getter, set: Setter)? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    static var level: Float? {
        get {
            guard let functions else { return nil }
            var value: Float = 0
            return functions.get(CGMainDisplayID(), &value) == 0 ? value : nil
        }
        set {
            guard let newValue, let functions else { return }
            _ = functions.set(CGMainDisplayID(), min(max(newValue, 0), 1))
        }
    }
}

/// The keyboard's backlight. macOS has no public interface for it; this uses the CoreBrightness
/// class the system's own slider uses, and reports nil when that is missing or the Mac has no
/// lit keyboard, in which case the keys are left to the system.
@MainActor
enum KeyboardLightControl {
    private typealias Getter = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Setter = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    private static let client: (object: NSObject, keyboard: UInt64, get: Getter, set: Setter)? = {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let object = type.init()
        let listSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard object.responds(to: getSelector), object.responds(to: setSelector), object.responds(to: listSelector),
              let list = object.perform(listSelector)?.takeRetainedValue() as? [NSNumber],
              let keyboard = list.first?.uint64Value,
              let get = class_getMethodImplementation(type, getSelector),
              let set = class_getMethodImplementation(type, setSelector)
        else { return nil }
        return (object, keyboard, unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    static var level: Float? {
        get {
            guard let client else { return nil }
            return client.get(client.object, getSelector, client.keyboard)
        }
        set {
            guard let newValue, let client else { return }
            _ = client.set(client.object, setSelector, min(max(newValue, 0), 1), client.keyboard)
        }
    }
}
