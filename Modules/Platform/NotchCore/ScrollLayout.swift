import CoreGraphics

/// Which ends of a scrolling area have more beyond them, so the area fades there instead of
/// cutting a card with a hard line. At rest at the start nothing fades at the start, and the
/// last row at the end stays clear.
public struct ScrollEdges: Equatable, Sendable {
    public var start: Bool
    public var end: Bool

    public init(start: Bool, end: Bool) {
        self.start = start
        self.end = end
    }

    /// - Parameters:
    ///   - offset: how far the content has scrolled from its start.
    ///   - visible: the length of the area that shows it.
    ///   - content: the length of all of it.
    public static func of(offset: CGFloat, visible: CGFloat, content: CGFloat) -> ScrollEdges {
        ScrollEdges(start: offset > 1, end: offset + visible < content - 1)
    }
}

/// How a row of like items is laid out in a page that may be short: when they all fit, in
/// rows of equal cells across the full width, the last row centred; when they do not, they
/// fill each column top to bottom and continue sideways, so a short notch scrolls sideways
/// and never down.
public enum RailLayout {
    public struct Plan: Equatable, Sendable {
        public let rows: Int
        public let columns: Int
        /// The items go on past the right edge and the rail scrolls sideways.
        public let scrolls: Bool
    }

    public static func plan(count: Int, item: CGSize, spacing: CGFloat, area: CGSize) -> Plan {
        guard count > 0 else { return Plan(rows: 0, columns: 0, scrolls: false) }
        let rowsFit = max(1, Int(((area.height + spacing) / (item.height + spacing)).rounded(.down)))
        let columnsFit = max(1, Int(((area.width + spacing) / (item.width + spacing)).rounded(.down)))
        if count <= rowsFit * columnsFit {
            let columns = min(count, columnsFit)
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            return Plan(rows: rows, columns: columns, scrolls: false)
        }
        let columns = Int((Double(count) / Double(rowsFit)).rounded(.up))
        return Plan(rows: rowsFit, columns: columns, scrolls: true)
    }
}

/// Whether a press on a notice acts when the button comes up: only if the same notice is
/// still showing and the button came up over it.
public enum NoticeClick {
    public static func acts(pressedID: String, shownID: String?, releasedInside: Bool) -> Bool {
        pressedID == shownID && releasedInside
    }
}

/// The value of a slider under the pointer, with a small zone at each end that counts as the
/// end itself.
public enum SliderValue {
    public static func fraction(at x: Double, width: Double, endZone: Double) -> Double {
        guard width > 2 * endZone else { return width > 0 ? min(max(x / width, 0), 1) : 0 }
        return min(max((x - endZone) / (width - 2 * endZone), 0), 1)
    }
}
