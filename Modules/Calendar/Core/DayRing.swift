import Foundation

/// A day as a ring of 24 hours: midnight at the top, going clockwise. Places are given as the
/// share of the day gone by, 0 at midnight and 1 at the next midnight, so a day of 23 or 25
/// hours (when the clocks change) still closes the ring.
public enum DayRing {
    /// How much of the day has gone by at `date`, kept within 0 and 1.
    public static func fraction(of date: Date, on day: Date, calendar: Calendar) -> Double {
        let (start, end) = bounds(of: day, calendar: calendar)
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / length, 0), 1)
    }

    /// Each timed event of the day as an arc, cut at the day's edges, in order of start.
    /// All-day events and events that do not touch the day have none.
    public static func arcs(for events: [AgendaEvent], on day: Date, calendar: Calendar) -> [ClosedRange<Double>] {
        let (start, end) = bounds(of: day, calendar: calendar)
        return events
            .filter { !$0.isAllDay && $0.end > start && $0.start < end }
            .sorted { $0.start < $1.start }
            .map { fraction(of: $0.start, on: day, calendar: calendar)...fraction(of: $0.end, on: day, calendar: calendar) }
    }

    private static func bounds(of day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}
