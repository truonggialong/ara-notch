import Foundation

/// The week a date is in, as a strip of seven days.
public enum WeekStrip {
    /// The seven days of the week `date` falls in, each at the start of its day, beginning
    /// on the calendar's first weekday.
    public static func days(around date: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -offset, to: start) else { return [start] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }
}

/// A day of the lunar calendar used in Vietnam and China, as it is said: day, then month.
public struct LunarDate: Equatable, Sendable {
    public let day: Int
    public let month: Int
    /// True in the repeated month of a leap year.
    public let isLeapMonth: Bool

    public init(day: Int, month: Int, isLeapMonth: Bool) {
        self.day = day
        self.month = month
        self.isLeapMonth = isLeapMonth
    }

    /// The lunar day a moment falls on. The system's lunisolar calendar is reckoned for
    /// China; on the rare days when a new moon falls within the hour between the two
    /// countries' clocks, Vietnam's calendar is a day apart.
    public init(_ date: Date) {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        let parts = calendar.dateComponents([.day, .month], from: date)
        self.init(day: parts.day ?? 1, month: parts.month ?? 1, isLeapMonth: parts.isLeapMonth ?? false)
    }

    /// "16/8"; a leap month carries a plus.
    public var text: String {
        "\(day)/\(month)" + (isLeapMonth ? "+" : "")
    }
}
