import CoreGraphics

/// Which display the notch lives on when several are connected.
public enum DisplayMode: String, CaseIterable, Sendable {
    /// Every display shows the notch; the one under the pointer is the one that answers.
    case all
    /// The display that has a notch; without one, the main display.
    case automatic
    /// The display with the active window.
    case main
    /// Whichever display the pointer is on.
    case pointer

    /// The notch that answers moves to the display the pointer goes to.
    public var followsPointer: Bool {
        self == .all || self == .pointer
    }
}

/// Picks the notch's display, and those that show it as well, from what is connected.
public enum DisplayChooser {
    public struct Candidate: Equatable, Sendable {
        public var hasNotch: Bool
        /// The display with the active window (and, by default, the menu bar).
        public var isMain: Bool
        public var containsPointer: Bool

        public init(hasNotch: Bool, isMain: Bool, containsPointer: Bool) {
            self.hasNotch = hasNotch
            self.isMain = isMain
            self.containsPointer = containsPointer
        }
    }

    /// Whether the pointer is on the display with this frame. Pointer positions are measured
    /// upwards from the bottom of the main display, so the top row of a display is at exactly
    /// its upper bound and its bottom row just above its lower one: a display holds its top
    /// edge and not its bottom edge, which is the top row of whatever is below it.
    public static func display(_ frame: CGRect, holds pointer: CGPoint) -> Bool {
        pointer.x >= frame.minX && pointer.x < frame.maxX && pointer.y > frame.minY && pointer.y <= frame.maxY
    }

    /// The index of the display to use; nil only when there are none.
    /// - Parameter current: the display the notch is on now. When the notch follows the
    ///   pointer and the pointer is on no display that is known, the notch stays there.
    public static func choose(_ mode: DisplayMode, among displays: [Candidate], current: Int? = nil) -> Int? {
        guard !displays.isEmpty else { return nil }
        let automatic = displays.firstIndex(where: \.hasNotch) ?? displays.firstIndex(where: \.isMain) ?? 0
        switch mode {
        case .automatic:
            return automatic
        case .main:
            return displays.firstIndex(where: \.isMain) ?? 0
        case .pointer, .all:
            let stay = current.flatMap { displays.indices.contains($0) ? $0 : nil }
            return displays.firstIndex(where: \.containsPointer) ?? stay ?? automatic
        }
    }

    /// The indexes of the other displays that show the notch as well, closed and only to be
    /// looked at: all of them when the notch is on every display, none otherwise.
    public static func others(_ mode: DisplayMode, among displays: [Candidate], current: Int? = nil) -> [Int] {
        guard mode == .all, let chosen = choose(mode, among: displays, current: current) else { return [] }
        return displays.indices.filter { $0 != chosen }
    }
}
