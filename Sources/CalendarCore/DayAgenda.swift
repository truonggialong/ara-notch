import Foundation

/// What is on one chosen day.
public enum DayAgenda {
    /// The events that touch the day `date` falls on: all-day ones first, then by start time.
    public static func events(on date: Date, from events: [AgendaEvent], calendar: Calendar) -> [AgendaEvent] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return events
            .filter { $0.start < end && $0.end > start }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return ($0.start, $0.id) < ($1.start, $1.id)
            }
    }
}

public extension WeekStrip {
    /// The same weekday a number of weeks later (or, negative, earlier), at the start of its day.
    static func shifting(_ date: Date, weeks: Int, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 7 * weeks, to: start) ?? start)
    }
}

/// An event being written on the notch: a title, a day, and a start time or the whole day.
public struct EventDraft: Equatable, Sendable {
    /// How long a timed event lasts until the user changes it in the calendar app.
    public static let duration: TimeInterval = 3600
    /// The start times offered: every half hour of the day, in minutes after midnight.
    public static let timeChoices: [Int] = Array(stride(from: 0, to: 24 * 60, by: 30))

    public var title: String
    public var day: Date
    /// Minutes after midnight; nil for an event that lasts the whole day.
    public var startMinutes: Int?

    public init(title: String, day: Date, startMinutes: Int?) {
        self.title = title
        self.day = day
        self.startMinutes = startMinutes
    }

    public var isAllDay: Bool { startMinutes == nil }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// When a new event on `day` starts until the user says otherwise: today, the next half
    /// hour that has not begun; on another day, nine in the morning.
    public static func defaultStartMinutes(on day: Date, now: Date, calendar: Calendar) -> Int {
        guard calendar.isDate(day, inSameDayAs: now) else { return 9 * 60 }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A half hour that has begun, even this very minute, is no longer offered.
        return min((minutes / 30 + 1) * 30, timeChoices.last ?? 0)
    }

    /// When the event starts and ends; nil when it has no title and so is not made.
    public func interval(calendar: Calendar) -> (start: Date, end: Date)? {
        guard !trimmedTitle.isEmpty else { return nil }
        let startOfDay = calendar.startOfDay(for: day)
        guard let startMinutes else {
            return (startOfDay, calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay)
        }
        let start = calendar.date(byAdding: .minute, value: startMinutes, to: startOfDay) ?? startOfDay
        return (start, start.addingTimeInterval(Self.duration))
    }
}

/// Links that open an event or a reminder in its own app.
public enum CalendarLinks {
    /// Opens the calendar app on an event. `itemID` is the identifier the system gives the
    /// calendar item; one occurrence of a repeating event is named by its start as well.
    public static func event(itemID: String, start: Date, isRepeating: Bool) -> URL? {
        guard !itemID.isEmpty else { return nil }
        var path = itemID
        if isRepeating {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            path = "\(formatter.string(from: start))/\(itemID)"
        }
        return URL(string: "ical://ekevent/\(path)?method=show&options=more")
    }

    /// Opens the reminders app on the reminder with this identifier.
    public static func reminder(id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(id)")
    }
}
