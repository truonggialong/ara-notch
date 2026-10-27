import CoreGraphics

/// Where the pointer is on a closed notch showing an activity that keeps its sides for itself
/// (playback controls, say).
public enum NotchActivityZone: Equatable, Sendable {
    /// Over the hardware notch: hovering opens the notch as usual.
    case middle
    /// Over the activity's sides or the strip under the notch: the activity takes the pointer,
    /// and the notch does not open.
    case own
    case outside
}

public enum NotchActivityZones {
    /// The zone of `point` (screen coordinates, y up). `closedRect` is the hardware notch,
    /// `sideWidth` and `bottomHeight` what the activity shows beside and under it, `padding`
    /// the reach around it that still counts as on it.
    public static func zone(
        of point: CGPoint, closedRect: CGRect, sideWidth: CGFloat, bottomHeight: CGFloat, padding: CGFloat
    ) -> NotchActivityZone {
        let shown = CGRect(
            x: closedRect.minX - sideWidth, y: closedRect.minY - bottomHeight,
            width: closedRect.width + 2 * sideWidth, height: closedRect.height + bottomHeight)
        let reach = shown.insetBy(dx: -max(0, padding), dy: -max(0, padding))
        // The top row of a display is at its frame's maxY, which CGRect.contains leaves out.
        guard point.x >= reach.minX, point.x <= reach.maxX, point.y >= reach.minY, point.y <= reach.maxY else {
            return .outside
        }
        let overNotch = point.x >= closedRect.minX && point.x <= closedRect.maxX
            && point.y >= closedRect.minY - (bottomHeight > 0 ? 0 : max(0, padding))
        return overNotch ? .middle : .own
    }
}
