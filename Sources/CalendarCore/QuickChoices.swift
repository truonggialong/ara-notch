import Foundation

/// A day offered for one click under the month of a picker: today and the two days after
/// it, the Saturday ahead, and this day next week.
public struct QuickDay: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case today, tomorrow, dayAfter, saturday, nextWeek
    }

    public let kind: Kind
    /// The day, at its start.
    public let day: Date

    public var id: String { kind.rawValue }

    /// The hours offered for one click under the clock, as minutes of the day: morning,
    /// noon, afternoon and evening.
    public static let minutesOfDay = [9 * 60, 12 * 60, 15 * 60, 19 * 60]

    /// The days to offer on a given day. The Saturday is the next one ahead, and is left
    /// out when another choice is that very day: from Thursday to Saturday.
    public static func choices(today: Date, calendar: Calendar) -> [QuickDay] {
        let start = calendar.startOfDay(for: today)
        func ahead(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: start) ?? start
        }
        var choices = [
            QuickDay(kind: .today, day: start),
            QuickDay(kind: .tomorrow, day: ahead(1)),
            QuickDay(kind: .dayAfter, day: ahead(2)),
        ]
        // Saturday is the seventh day of the week as calendars count them.
        let untilSaturday = (7 - calendar.component(.weekday, from: start) + 7) % 7
        if (3...6).contains(untilSaturday) {
            choices.append(QuickDay(kind: .saturday, day: ahead(untilSaturday)))
        }
        choices.append(QuickDay(kind: .nextWeek, day: ahead(7)))
        return choices
    }
}
