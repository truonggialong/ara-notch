import NotchShell
import SwiftUI
import SystemEventsCore

/// Builds the notices for system events: each a sign the notch grows into for a moment,
/// naming what speaks on the left and saying what happened on the right.
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

    static func power(_ event: PowerEvent) -> NotchLiveActivity {
        let mark = L10n.string("sign.battery")
        func row(_ key: String, _ percent: Int, isLow: Bool = false) -> [AraSign.Row] {
            [AraSign.Row(L10n.string(key), badge: isLow ? .disc("\(percent)%") : .digits("\(percent)%"))]
        }
        switch event {
        case .pluggedIn(let percent):
            return activity(
                ID.power, priority: 2, duration: 3,
                AraSign(icon: .symbol("battery.100percent.bolt"), mark: mark, rows: row("alert.power.charging", percent)))
        case .unplugged(let percent):
            return activity(
                ID.power, priority: 2, duration: 3,
                AraSign(icon: .symbol(batterySymbol(percent)), mark: mark, rows: row("alert.power.onBattery", percent)))
        case .low(let percent):
            return activity(
                ID.power, priority: 3, duration: 5,
                AraSign(
                    tone: .danger, icon: .symbol("battery.25percent"), mark: mark,
                    rows: row("alert.power.low", percent, isLow: true)))
        case .full:
            return activity(
                ID.power, priority: 2, duration: 3,
                AraSign(icon: .symbol("battery.100percent"), mark: mark, rows: row("alert.power.full", 100)))
        }
    }

    /// The mark that rests beside the notch while Caps Lock is on. Above the track playing.
    static func capsLockResting() -> NotchLiveActivity {
        var activity = NotchLiveActivity(id: ID.capsLockResting, priority: 1, duration: 0) {
            Image(systemName: "capslock.fill")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityLabel(L10n.string("alert.capsLock.on"))
        } trailing: {
            EmptyView()
        }
        // A mark, not a line of text: the notch widens just enough for it.
        activity.sideWidth = 36
        return activity
    }

    static func capsLock(_ event: CapsLockEvent) -> NotchLiveActivity {
        activity(
            ID.capsLock, priority: 1, duration: 1.5,
            AraSign(
                icon: .symbol(event == .on ? "capslock.fill" : "capslock"), mark: "Caps Lock",
                rows: [AraSign.Row(L10n.string(event == .on ? "alert.capsLock.on" : "alert.capsLock.off"))]))
    }

    static func network(_ event: ConnectivityEvent) -> NotchLiveActivity {
        let mark = L10n.string("sign.network")
        switch event {
        case .offline:
            return activity(
                ID.network, priority: 3, duration: 4,
                AraSign(
                    tone: .attention, icon: .symbol("wifi.slash"), mark: mark,
                    rows: [AraSign.Row(L10n.string("alert.network.offline"))]))
        case .online:
            return activity(
                ID.network, priority: 2, duration: 2,
                AraSign(icon: .symbol("wifi"), mark: mark, rows: [AraSign.Row(L10n.string("alert.network.online"))]))
        }
    }

    static func bluetooth(name: String, isConnected: Bool) -> NotchLiveActivity {
        let symbol = BluetoothDeviceKind.guess(fromName: name).symbolName
        let label = name.isEmpty ? L10n.string("alert.bluetooth.device") : name
        return activity(
            ID.bluetooth, priority: 2, duration: 3,
            AraSign(
                icon: .symbol(symbol), mark: "Bluetooth",
                rows: [AraSign.Row(
                    label, detail: L10n.string(isConnected ? "alert.bluetooth.connected" : "alert.bluetooth.disconnected"))]))
    }

    private static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Volume, brightness or the keyboard's light: its name on the left, a bar and the
    /// level in digits on the right.
    /// - Parameter nameKey: the string key of what is being set.
    static func level(_ nameKey: String, symbol: String, value: Float) -> NotchLiveActivity {
        let level = Double(min(max(value, 0), 1))
        return activity(
            ID.level, priority: 3, duration: 1.5,
            AraSign(
                icon: .symbol(symbol), mark: L10n.string(nameKey),
                rows: [AraSign.Row("", badge: .digits("\(Int((level * 100).rounded()))%"), level: level)]))
    }

    static func volumeSymbol(level: Float, isMuted: Bool) -> String {
        if isMuted || level <= 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private static func activity(_ id: String, priority: Int, duration: TimeInterval, _ sign: AraSign) -> NotchLiveActivity {
        NotchLiveActivity(id: id, priority: priority, duration: duration, sign: sign)
    }
}

extension BluetoothDeviceKind {
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
