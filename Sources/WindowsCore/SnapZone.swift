import CoreGraphics
import Foundation

/// A place on the display a window can be snapped to.
public enum SnapZone: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    /// Centred, two thirds of the width and height.
    case center

    /// The zone's frame inside a display's usable area. AppKit coordinates: origin bottom-left.
    public func frame(in visible: CGRect) -> CGRect {
        let halfWidth = visible.width / 2
        let halfHeight = visible.height / 2
        switch self {
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.minX + halfWidth, y: visible.minY, width: halfWidth, height: visible.height)
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.minY + halfHeight, width: visible.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: visible.minX, y: visible.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: visible.minX + halfWidth, y: visible.minY + halfHeight, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visible.minX + halfWidth, y: visible.minY, width: halfWidth, height: halfHeight)
        case .maximize:
            return visible
        case .center:
            let width = (visible.width * 2 / 3).rounded()
            let height = (visible.height * 2 / 3).rounded()
            return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        }
    }

    /// The global shortcut that snaps the front window to this zone: Control-Option plus a key.
    public var shortcut: SnapShortcut {
        let (keyCode, symbol): (UInt32, String) = switch self {
        case .leftHalf: (123, "←")
        case .rightHalf: (124, "→")
        case .topHalf: (126, "↑")
        case .bottomHalf: (125, "↓")
        case .topLeft: (32, "U")
        case .topRight: (34, "I")
        case .bottomLeft: (38, "J")
        case .bottomRight: (40, "K")
        case .maximize: (36, "↩")
        case .center: (8, "C")
        }
        return SnapShortcut(keyCode: keyCode, modifiers: [.control, .option], display: "⌃⌥\(symbol)")
    }
}

public struct SnapShortcut: Equatable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    /// The virtual key code.
    public let keyCode: UInt32
    public let modifiers: Modifiers
    /// How the shortcut is written for the user, e.g. "⌃⌥←".
    public let display: String
}

public enum SnapGeometry {
    /// Windows of other apps are moved in coordinates whose origin is the top-left corner of
    /// the primary display, with y growing downwards. This is where a frame's top-left corner is.
    public static func topLeftOrigin(of frame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX, y: primaryScreenHeight - frame.maxY)
    }

    /// The reverse: an AppKit frame from a top-left origin and a size.
    public static func frame(topLeft: CGPoint, size: CGSize, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: topLeft.x, y: primaryScreenHeight - topLeft.y - size.height, width: size.width, height: size.height)
    }

    /// The display that shows most of the window; the first display when it is on none.
    public static func displayIndex(for window: CGRect, among displays: [CGRect]) -> Int? {
        guard !displays.isEmpty else { return nil }
        let areas = displays.map { display -> CGFloat in
            let overlap = display.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = areas.max(), best > 0 else { return 0 }
        return areas.firstIndex(of: best)
    }
}

/// Reads and writes the window settings.
public struct WindowSettingsStore {
    public enum Key {
        public static let snapEnabled = "windows.snapEnabled"
        public static let edgeSnapEnabled = "windows.edgeSnapEnabled"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Snap a window when it is dragged to an edge of the display. Off by default.
    public var edgeSnapEnabled: Bool {
        get { defaults.object(forKey: Key.edgeSnapEnabled) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.edgeSnapEnabled) }
    }

    /// Off by default: the shortcuts are global and may clash with another window manager.
    public var snapEnabled: Bool {
        get { defaults.object(forKey: Key.snapEnabled) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.snapEnabled) }
    }
}
