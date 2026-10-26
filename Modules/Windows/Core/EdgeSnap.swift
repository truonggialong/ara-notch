import CoreGraphics

/// Decides where a window snaps when it is dragged to an edge of the display.
public enum EdgeSnap {
    /// How close to an edge the pointer must be, in points.
    public static let margin: CGFloat = 6
    /// How far along a side edge, from a corner, still counts as that corner.
    public static let cornerReach: CGFloat = 120
    /// A window must move at least this far before a drag counts as moving it.
    public static let minimumMove: CGFloat = 8

    /// The zone for a pointer position on a display, or nil away from the edges. The left and
    /// right edges give halves, the top edge the whole area, corners give quarters. The bottom
    /// edge alone gives nothing.
    /// - Parameter screen: the display's full frame, AppKit coordinates (origin bottom-left).
    public static func zone(at point: CGPoint, in screen: CGRect) -> SnapZone? {
        guard screen.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        let atLeft = point.x <= screen.minX + margin
        let atRight = point.x >= screen.maxX - margin
        let atTop = point.y >= screen.maxY - margin
        let atBottom = point.y <= screen.minY + margin
        let nearTop = point.y >= screen.maxY - cornerReach
        let nearBottom = point.y <= screen.minY + cornerReach
        let nearLeft = point.x <= screen.minX + cornerReach
        let nearRight = point.x >= screen.maxX - cornerReach

        if atLeft {
            return nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf
        }
        if atRight {
            return nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf
        }
        if atTop {
            return nearLeft ? .topLeft : nearRight ? .topRight : .maximize
        }
        if atBottom {
            return nearLeft ? .bottomLeft : nearRight ? .bottomRight : nil
        }
        return nil
    }

    /// Whether a window's origin changed enough to say the user is dragging it.
    public static func hasMoved(from start: CGPoint, to current: CGPoint) -> Bool {
        abs(current.x - start.x) >= minimumMove || abs(current.y - start.y) >= minimumMove
    }
}
