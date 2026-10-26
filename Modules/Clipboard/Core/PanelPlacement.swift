import CoreGraphics

/// Positions a floating panel next to the pointer. Coordinates have a bottom-left origin.
public enum PanelPlacement {
    public static let cursorOffset: CGFloat = 12

    /// The panel's top-left corner goes just below and right of `point`, then the panel is moved
    /// back inside `visibleFrame`. A panel larger than that area is pinned to its top-left corner.
    public static func frame(size: CGSize, near point: CGPoint, in visibleFrame: CGRect) -> CGRect {
        var x = point.x + cursorOffset
        var y = point.y - cursorOffset - size.height

        // The later clamp wins when both cannot hold: left edge and top edge take priority.
        x = min(x, visibleFrame.maxX - size.width)
        x = max(x, visibleFrame.minX)
        y = max(y, visibleFrame.minY)
        y = min(y, visibleFrame.maxY - size.height)

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
