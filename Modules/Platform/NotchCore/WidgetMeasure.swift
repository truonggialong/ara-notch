import Foundation

/// How much of a widget's bars to fill.
public enum WidgetMeasure {
    /// A share of a bar, kept within 0 and 1; what is no number fills nothing.
    public static func fraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Where a span of a bar starts and how long it is, as shares of the bar: kept on the bar,
    /// and never shorter than `minimumShare`, widened inwards when it sits at an end.
    public static func span(_ range: ClosedRange<Double>, minimumShare: Double) -> (start: Double, length: Double) {
        let lower = fraction(range.lowerBound), upper = fraction(range.upperBound)
        let length = min(max(upper - lower, minimumShare), 1)
        return (min(lower, 1 - length), length)
    }

    /// How many of `count` segments a charge lights. Any charge at all lights one, so a nearly
    /// empty battery does not look like none.
    public static func segments(percent: Int, of count: Int) -> Int {
        guard percent > 0, count > 0 else { return 0 }
        let share = Double(min(percent, 100)) / 100 * Double(count)
        return max(1, Int(share.rounded()))
    }
}
