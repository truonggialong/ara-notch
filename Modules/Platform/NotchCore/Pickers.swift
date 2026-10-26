import Foundation

/// The geometry of the clock face a time is chosen on. Angles are in degrees, clockwise
/// from twelve o'clock.
public enum ClockDial {
    /// The hours of the outer ring, from the top: those of a wall clock.
    public static let outerHours = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    /// The hours of the inner ring, from the top: midnight, then the afternoon and evening.
    public static let innerHours = [0, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
    /// How far from the centre, as a share of the radius, the inner ring ends.
    public static let innerShare = 0.72

    /// The angle of a point from the centre of the face; `dy` grows downwards, as on screen.
    public static func angle(dx: Double, dy: Double) -> Double {
        let degrees = atan2(dx, -dy) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    public static func isInner(distance: Double, radius: Double) -> Bool {
        distance < radius * innerShare
    }

    /// The hour nearest to an angle on one of the two rings.
    public static func hour(angle: Double, isInner: Bool) -> Int {
        let index = Int((angle / 30).rounded()) % 12
        return (isInner ? innerHours : outerHours)[index]
    }

    public static func place(ofHour hour: Int) -> (angle: Double, isInner: Bool) {
        if let index = outerHours.firstIndex(of: hour) {
            return (Double(index) * 30, false)
        }
        return (Double(innerHours.firstIndex(of: hour) ?? 0) * 30, true)
    }

    /// The minute nearest to an angle: the whole face is one hour.
    public static func minute(angle: Double) -> Int {
        Int((angle / 6).rounded()) % 60
    }

    public static func angle(ofMinute minute: Int) -> Double {
        Double(minute) * 6
    }

    /// For a length rather than a time of day: the hours 0 to 3, a quarter of the face each.
    public static func lengthHour(angle: Double) -> Int {
        Int((angle / 90).rounded()) % 4
    }

    public static func angle(ofLengthHour hour: Int) -> Double {
        Double(hour) * 90
    }

    public static func minutesOfDay(hour: Int, minute: Int) -> Int {
        hour * 60 + minute
    }

    /// "14:05": the time of day as the face's heading shows it.
    public static func text(minutesOfDay: Int) -> String {
        String(format: "%02d:%02d", minutesOfDay / 60, minutesOfDay % 60)
    }
}

/// A month laid out in weeks, for choosing a day by sight.
public struct MonthGrid: Equatable, Sendable {
    /// The first day of the month, at its start.
    public let month: Date
    /// Rows of seven places from the calendar's first weekday; nil where the month has no day.
    public let weeks: [[Date?]]

    public init(containing date: Date, calendar: Calendar) {
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        self.month = month
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var places = [Date?](repeating: nil, count: lead)
        for offset in 0..<count {
            places.append(calendar.date(byAdding: .day, value: offset, to: month))
        }
        while places.count % 7 != 0 {
            places.append(nil)
        }
        weeks = stride(from: 0, to: places.count, by: 7).map { Array(places[$0..<$0 + 7]) }
    }

    /// The first day of the month some months before or after the one `date` is in.
    public static func shifting(_ date: Date, months: Int, calendar: Calendar) -> Date {
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return calendar.date(byAdding: .month, value: months, to: month) ?? month
    }

    /// A day and a time of day put together.
    public static func moment(on day: Date, minutesOfDay: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minutesOfDay, to: calendar.startOfDay(for: day)) ?? day
    }

    public static func minutesOfDay(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// Settings the app no longer uses, removed at launch so nothing is kept for no purpose:
/// the names typed before, once offered again as suggestions (until 0.22.1), and the
/// calendar page's size, which now fits what it shows (until 0.21.0).
public enum RetiredSettings {
    public static let keys = ["recentNames.event", "recentNames.reminder", "recentNames.timer", "calendar.pageSize"]

    public static func remove(from defaults: UserDefaults) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
