import CoreAudio
import Foundation
import MediaCore

/// Lists the sound output devices and switches between them, through Core Audio.
@MainActor
enum AudioOutputs {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Every device that can play sound, in the system's order.
    static func all() -> [AudioOutput] {
        var devicesAddress = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputChannels(id), let name = name(of: id) else { return nil }
            return AudioOutput(id: id, name: name, transport: AudioOutput.Transport(code: transport(of: id)))
        }
    }

    /// The device sound currently goes to.
    static func current() -> AudioObjectID? {
        var defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &size, &id) == noErr, id != 0 else {
            return nil
        }
        return id
    }

    /// Sends sound to this device from now on. Returns false when the system refuses.
    @discardableResult
    static func select(_ id: AudioObjectID) -> Bool {
        var defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        return AudioObjectSetPropertyData(system, &defaultAddress, 0, nil, size, &id) == noErr
    }

    /// 'vmvc': the device's overall volume, as the system's own slider sets it.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    /// The current output's volume, 0…1; nil when the device has none the system can set.
    static var volume: Float? {
        get {
            guard let device = current() else { return nil }
            var volumeAddress = address(virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        set {
            guard let newValue, let device = current() else { return }
            var volumeAddress = address(virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
            var value = Float32(min(max(newValue, 0), 1))
            _ = AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    private static func hasOutputChannels(_ id: AudioObjectID) -> Bool {
        var streamsAddress = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioObjectID) -> String? {
        var nameAddress = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func transport(of id: AudioObjectID) -> UInt32 {
        var transportAddress = address(kAudioDevicePropertyTransportType)
        var code: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &size, &code)
        return code
    }
}
