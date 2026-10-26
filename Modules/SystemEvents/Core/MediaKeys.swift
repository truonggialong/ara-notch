import Foundation

/// A press or release of one of the keys whose on-screen display the notch can take over.
public struct MediaKeyEvent: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case volumeUp
        case volumeDown
        case mute
        case brightnessUp
        case brightnessDown
        case keyboardLightUp
        case keyboardLightDown
    }

    public let key: Key
    public let isDown: Bool
    /// The key is being held and repeats.
    public let isRepeat: Bool

    /// - Parameter data1: the `data1` field of a system-defined event of the special-key
    ///   subtype: key code in the high 16 bits, then the state (0xA down, 0xB up), then the
    ///   repeat flag in the lowest bit. Nil for keys the notch does not handle.
    public init?(data1: Int) {
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 21: key = .keyboardLightUp
        case 22: key = .keyboardLightDown
        default: return nil
        }
        isDown = (data1 & 0xFF00) >> 8 == 0xA
        isRepeat = data1 & 0x1 == 1
    }
}

/// Moves a 0…1 level the way the volume and brightness keys do.
public enum LevelStepper {
    public static let steps: Float = 16

    /// One step up or down, landing on a step boundary. A fine step is a quarter of a step.
    public static func step(_ level: Float, up: Bool, fine: Bool = false) -> Float {
        let count = fine ? steps * 4 : steps
        let position = level * count
        // A level sitting between two steps goes to the nearer boundary in that direction.
        let next = up ? (position + 0.001).rounded(.down) + 1 : (position - 0.001).rounded(.up) - 1
        return min(max(next / count, 0), 1)
    }
}
