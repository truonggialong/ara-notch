import Foundation

/// A device sound can be played through.
public struct AudioOutput: Equatable, Identifiable, Sendable {
    public enum Transport: Equatable, Sendable {
        case builtIn
        case bluetooth
        case airPlay
        case usb
        /// A monitor or TV, over HDMI or DisplayPort.
        case display
        /// A software device, or several devices combined.
        case virtual
        case other

        /// - Parameter code: the system's four-character transport type, e.g. `'bltn'`.
        public init(code: UInt32) {
            switch code {
            case Self.fourCharacters("bltn"): self = .builtIn
            case Self.fourCharacters("blue"), Self.fourCharacters("blea"): self = .bluetooth
            case Self.fourCharacters("airp"): self = .airPlay
            case Self.fourCharacters("usb "): self = .usb
            case Self.fourCharacters("hdmi"), Self.fourCharacters("dprt"): self = .display
            case Self.fourCharacters("virt"), Self.fourCharacters("grup"): self = .virtual
            default: self = .other
            }
        }

        private static func fourCharacters(_ text: String) -> UInt32 {
            text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
        }
    }

    /// The system's identifier of the device; valid until the device goes away.
    public let id: UInt32
    public let name: String
    public let transport: Transport

    public init(id: UInt32, name: String, transport: Transport) {
        self.id = id
        self.name = name
        self.transport = transport
    }

    /// An SF Symbol for the device, from how it is connected and what it is called.
    public var symbolName: String {
        let name = name.lowercased()
        let isHeadphones = name.contains("headphone") || name.contains("headset") || name.contains("tai nghe")
        switch transport {
        case .builtIn:
            return isHeadphones ? "headphones" : "laptopcomputer"
        case .bluetooth:
            if name.contains("airpods max") { return "airpodsmax" }
            if name.contains("airpods pro") { return "airpodspro" }
            if name.contains("airpods") { return "airpods" }
            return isHeadphones ? "headphones" : "hifispeaker"
        case .airPlay: return "airplayaudio"
        case .usb: return isHeadphones ? "headphones" : "cable.connector"
        case .display: return "display"
        case .virtual: return "waveform"
        case .other: return "speaker.wave.2"
        }
    }
}
