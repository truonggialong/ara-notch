import CoreGraphics

/// How far two fingers must travel for a swipe to count.
public enum SwipeSensitivity: String, CaseIterable, Sendable {
    case low
    case medium
    case high

    /// Travel, in points of scroll distance.
    public var threshold: CGFloat {
        switch self {
        case .low: 60
        case .medium: 35
        case .high: 15
        }
    }
}

/// Recognises one vertical two-finger swipe per gesture: down opens the notch, up closes it.
public struct VerticalSwipeDetector: Sendable {
    public enum Direction: Equatable, Sendable {
        case down
        case up
    }

    public enum Phase: Equatable, Sendable {
        case began
        case changed
        case ended
        case cancelled
        /// Inertial scrolling after the fingers lifted.
        case momentum
        /// A mouse wheel: single notches without a gesture around them.
        case wheel
    }

    public var threshold: CGFloat

    private var sumX: CGFloat = 0
    private var sumY: CGFloat = 0
    private var fired = false

    public init(threshold: CGFloat) {
        self.threshold = threshold
    }

    /// - Parameter fingerDeltaY: positive when the fingers (or the wheel) move down; see `fingerDelta`.
    public mutating func add(deltaX: CGFloat, fingerDeltaY: CGFloat, phase: Phase) -> Direction? {
        switch phase {
        case .wheel:
            if fingerDeltaY == 0 { return nil }
            return fingerDeltaY > 0 ? .down : .up
        case .ended, .cancelled:
            reset()
            return nil
        case .momentum:
            return nil
        case .began:
            reset()
        case .changed:
            break
        }

        sumX += deltaX
        sumY += fingerDeltaY
        guard !fired, abs(sumY) >= threshold, abs(sumY) > abs(sumX) else { return nil }
        fired = true
        return sumY > 0 ? .down : .up
    }

    /// The fingers' vertical movement, from a scroll event's delta. With natural scrolling the
    /// system reports the fingers' own direction; without it, the opposite.
    public static func fingerDelta(scrollingDeltaY: CGFloat, isNatural: Bool) -> CGFloat {
        isNatural ? scrollingDeltaY : -scrollingDeltaY
    }

    private mutating func reset() {
        sumX = 0
        sumY = 0
        fired = false
    }
}
