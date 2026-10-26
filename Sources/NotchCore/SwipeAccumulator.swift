import CoreGraphics

/// Turns the scroll deltas of one trackpad gesture into at most one page switch.
public struct SwipeAccumulator: Sendable {
    public enum Direction: Equatable, Sendable {
        case next
        case previous
    }

    public enum Phase: Equatable, Sendable {
        case began
        case changed
        case ended
        case cancelled
        /// Inertial scrolling after the fingers lifted.
        case momentum
    }

    public static let threshold: CGFloat = 40

    private var sumX: CGFloat = 0
    private var sumY: CGFloat = 0
    private var fired = false

    public init() {}

    public mutating func add(deltaX: CGFloat, deltaY: CGFloat, phase: Phase) -> Direction? {
        switch phase {
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
        sumY += deltaY
        guard !fired, abs(sumX) >= Self.threshold, abs(sumX) > abs(sumY) else { return nil }
        fired = true
        // Fingers moving left produce negative deltas and reveal the next page.
        return sumX < 0 ? .next : .previous
    }

    private mutating func reset() {
        sumX = 0
        sumY = 0
        fired = false
    }
}

/// Lets a mouse wheel, which only turns up and down, move a row that scrolls sideways.
public enum WheelRedirect {
    /// The sideways travel a wheel's turn should become, or nil when the scroll is left as it
    /// is: one from a trackpad or a touch surface, or one already more sideways than not.
    public static func sideways(deltaX: Double, deltaY: Double, isTouch: Bool) -> Double? {
        guard !isTouch, deltaY != 0, abs(deltaY) > abs(deltaX) else { return nil }
        return deltaY
    }
}
