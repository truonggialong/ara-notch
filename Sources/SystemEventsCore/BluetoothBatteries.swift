import Foundation

/// A Bluetooth device connected now, with its battery as the system reports it.
public struct BluetoothBattery: Equatable, Sendable {
    public let name: String
    public let kind: BluetoothDeviceKind
    /// 0…100; nil for a device that reports no battery.
    public let percent: Int?

    public init(name: String, kind: BluetoothDeviceKind, percent: Int?) {
        self.name = name
        self.kind = kind
        self.percent = percent
    }
}

/// Reads the battery levels macOS lists for connected Bluetooth devices
/// (`system_profiler SPBluetoothDataType -json`), which needs no permission. A device with a
/// left and a right bud counts the lower one; a charging case does not count.
public enum BluetoothBatteries {
    /// The connected devices in the report's order; nil when the report cannot be read.
    public static func parse(_ json: Data) -> [BluetoothBattery]? {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }
        return controllers.flatMap { controller -> [BluetoothBattery] in
            let connected = controller["device_connected"] as? [[String: Any]] ?? []
            return connected.flatMap { entry in
                entry.compactMap { name, value -> BluetoothBattery? in
                    guard let fields = value as? [String: Any] else { return nil }
                    return BluetoothBattery(name: name, kind: kind(of: fields, name: name), percent: percent(of: fields))
                }
            }
        }
    }

    private static func percent(of fields: [String: Any]) -> Int? {
        func level(_ key: String) -> Int? {
            (fields[key] as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        }
        if let main = level("device_batteryLevelMain") { return main }
        let buds = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
        return buds.min()
    }

    private static func kind(of fields: [String: Any], name: String) -> BluetoothDeviceKind {
        switch (fields["device_minorType"] as? String)?.lowercased() {
        case "headphones", "headset": .headphones
        case "mouse": .mouse
        case "keyboard": .keyboard
        case "trackpad": .trackpad
        case "gamepad", "joystick": .gamepad
        case "speaker", "hi-fi stereo", "loudspeaker": .speaker
        case "phone", "smartphone", "cellular": .phone
        default: BluetoothDeviceKind.guess(fromName: name)
        }
    }
}
