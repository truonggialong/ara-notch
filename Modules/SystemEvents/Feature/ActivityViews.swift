import NotchShell
import SwiftUI
import SystemEventsCore

/// Builds the notices for system events, in the notch's pictures (`AraGlance`): what speaks left
/// of the camera, how much or which on the right; words only where a name or a number matters.
@MainActor
enum SystemActivities {
    enum ID {
        static let power = "power"
        static let capsLock = "capslock"
        static let capsLockResting = "capslock.on"
        static let network = "network"
        static let bluetooth = "bluetooth"
        static let level = "level"
    }

    /// Charging, on battery and full read from the picture: the battery's five cells. A low
    /// battery says how much is left, in red, since that number is what matters then.
    static func power(_ event: PowerEvent) -> NotchLiveActivity {
        let mark = L10n.string("sign.battery")
        switch event {
        case .pluggedIn(let percent):
            return glance(
                ID.power, priority: 2, duration: 3, detail: "\(mark) · \(L10n.string("alert.power.charging")) \(percent)%",
                AraGlance(.bolt, color: .done, motion: .blink, value: .cells(BatteryCells.lit(percent: percent))))
        case .unplugged(let percent):
            return glance(
                ID.power, priority: 2, duration: 3, detail: "\(mark) · \(L10n.string("alert.power.onBattery")) \(percent)%",
                AraGlance(.plug, value: .cells(BatteryCells.lit(percent: percent))))
        case .low(let percent):
            return glance(
                ID.power, priority: 3, duration: 5, detail: "\(L10n.string("alert.power.low")) \(percent)%",
                AraGlance(.battery, color: .warning, motion: .blink, value: .text("\(percent)%"), valueColor: .warning))
        case .full:
            return glance(
                ID.power, priority: 2, duration: 3, detail: "\(mark) · \(L10n.string("alert.power.full"))",
                AraGlance(.battery, color: .done, value: .cells(BatteryCells.count)))
        }
    }

    /// The mark that rests beside the notch while Caps Lock is on. Above the track playing.
    static func capsLockResting() -> NotchLiveActivity {
        NotchLiveActivity(
            id: ID.capsLockResting, priority: 1, duration: 0,
            glance: AraGlance(.capsLock, color: .timer, value: .light(beating: false)),
            detail: L10n.string("alert.capsLock.on"))
    }

    /// The key with its light on, or off.
    static func capsLock(_ event: CapsLockEvent) -> NotchLiveActivity {
        glance(
            ID.capsLock, priority: 1, duration: 1.5,
            detail: "Caps Lock · \(L10n.string(event == .on ? "alert.capsLock.on" : "alert.capsLock.off"))",
            event == .on
                ? AraGlance(.capsLock, color: .timer, value: .light(beating: false))
                : AraGlance(.capsLock, value: .light(beating: false), valueColor: .plain))
    }

    /// Back online reads from the picture; offline says so in words, in red.
    static func network(_ event: ConnectivityEvent) -> NotchLiveActivity {
        switch event {
        case .offline:
            return glance(
                ID.network, priority: 3, duration: 4, detail: L10n.string("alert.network.offline"),
                AraGlance(.wifiOff, color: .warning, value: .text(L10n.string("glance.offline")), valueColor: .warning))
        case .online:
            return glance(
                ID.network, priority: 2, duration: 2, detail: L10n.string("alert.network.online"),
                AraGlance(.wifi, color: .done, value: .done))
        }
    }

    /// The device's picture on the left and its name on the right: which of several earbuds
    /// or keyboards it was. Gone, the picture is dimmed.
    static func bluetooth(name: String, isConnected: Bool) -> NotchLiveActivity {
        let label = name.isEmpty ? L10n.string("alert.bluetooth.device") : name
        let state = L10n.string(isConnected ? "alert.bluetooth.connected" : "alert.bluetooth.disconnected")
        return glance(
            ID.bluetooth, priority: 2, duration: 3, detail: "\(label) · \(state)",
            AraGlance(
                BluetoothDeviceKind.guess(fromName: name).glanceIcon(name: name), motion: isConnected ? .drop : .none,
                value: .text(label), valueColor: isConnected ? nil : .plain))
    }

    /// What is being set, and a bar for its level: the number is in the bar.
    enum Level {
        case volume(muted: Bool), brightness, keyboardLight

        var pictogram: AraPictogram {
            switch self {
            case let .volume(muted): muted ? .mute : .speaker
            case .brightness: .sun
            case .keyboardLight: .keyLight
            }
        }

        var nameKey: String {
            switch self {
            case .volume: "sign.volume"
            case .brightness: "sign.brightness"
            case .keyboardLight: "sign.keyboardLight"
            }
        }
    }

    /// Volume, brightness or the keyboard's light. Pressed again and again, the same notice
    /// stays and its bar moves.
    static func level(_ kind: Level, value: Float) -> NotchLiveActivity {
        let level = Double(min(max(value, 0), 1))
        let color: AraNoticeColor = switch kind {
        case .volume(true): .warning
        case .brightness: .awake
        default: .plain
        }
        return glance(
            ID.level, priority: 3, duration: 1.5,
            detail: "\(L10n.string(kind.nameKey)) \(Int((level * 100).rounded()))%",
            AraGlance(kind.pictogram, color: color, value: .meter(level), valueColor: color == .warning ? .plain : color))
    }

    static func volumeSymbol(level: Float, isMuted: Bool) -> String {
        if isMuted || level <= 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private static func glance(
        _ id: String, priority: Int, duration: TimeInterval, detail: String, _ glance: AraGlance
    ) -> NotchLiveActivity {
        NotchLiveActivity(id: id, priority: priority, duration: duration, glance: glance, detail: detail)
    }
}

extension BluetoothDeviceKind {
    /// The picture of a device of this kind: earbuds for names that say so, else the kind's.
    func glanceIcon(name: String) -> AraGlance.Icon {
        let lower = name.lowercased()
        switch self {
        case .headphones:
            return .pictogram(lower.contains("airpods") || lower.contains("buds") ? .earbuds : .headphones)
        case .keyboard: return .pictogram(.keyboard)
        case .mouse: return .pictogram(.mouse)
        case .speaker: return .pictogram(.speaker)
        default: return .symbol(symbolName)
        }
    }

    /// The system symbol drawn for a device of this kind.
    var symbolName: String {
        switch self {
        case .headphones: "headphones"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gamepad: "gamecontroller"
        case .speaker: "hifispeaker"
        case .phone: "iphone"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}
