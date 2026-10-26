import Foundation

/// What sort of Bluetooth device this probably is, for choosing an icon.
public enum BluetoothDeviceKind: Equatable, Sendable {
    case headphones
    case keyboard
    case mouse
    case trackpad
    case gamepad
    case speaker
    case phone
    case other

    /// Guessed from the device name, which is all a connect notification reliably gives.
    /// Checked in order: the first group with a matching word wins.
    public static func guess(fromName name: String) -> BluetoothDeviceKind {
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
        let words = Set(folded.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init))

        for (kind, fragments, wholeWords) in hints {
            if fragments.contains(where: folded.contains) || !words.isDisjoint(with: wholeWords) {
                return kind
            }
        }
        return .other
    }

    /// Substrings that identify a kind, and short words that only count as whole words
    /// ("loa" must not match inside another word).
    private static let hints: [(BluetoothDeviceKind, [String], Set<String>)] = [
        (.headphones, ["airpods", "beats", "buds", "headphone", "headset", "earbud", "earphone", "wh-", "wf-", "tai nghe"], []),
        (.keyboard, ["keyboard", "keychron", "ban phim"], []),
        (.trackpad, ["trackpad"], []),
        (.mouse, ["mouse", "mx master", "mx anywhere", "chuot"], []),
        (.gamepad, ["controller", "dualsense", "dualshock", "xbox", "gamepad", "joy-con"], []),
        (.speaker, ["speaker", "homepod", "soundlink"], ["jbl", "loa"]),
        (.phone, ["iphone", "galaxy", "pixel"], ["phone"]),
    ]
}

/// Drops repeated connect or disconnect notifications for the same device; the system often
/// sends several for one event.
public struct BluetoothEventFilter: Sendable {
    public static let window: TimeInterval = 5

    private var last: [String: (isConnected: Bool, at: Date)] = [:]

    public init() {}

    public mutating func shouldReport(deviceID: String, isConnected: Bool, at now: Date) -> Bool {
        // The window is measured from the last event that was reported, so a steady stream of
        // duplicates cannot keep pushing it forward.
        if let previous = last[deviceID], previous.isConnected == isConnected,
           now.timeIntervalSince(previous.at) < Self.window {
            return false
        }
        last[deviceID] = (isConnected, now)
        return true
    }
}

/// The Bluetooth devices connected now, by name, for the overview's device tile.
public struct ConnectedDevices: Equatable, Sendable {
    private var byID: [String: String] = [:]

    public init() {}

    public mutating func connected(id: String, name: String) {
        byID[id] = name
    }

    public mutating func disconnected(id: String) {
        byID[id] = nil
    }

    /// The names in alphabetical order; a device with no name is left out.
    public var names: [String] {
        byID.values.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
