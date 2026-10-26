import Foundation

/// What is left of today, for the calendar widget: how many events and reminders are still to
/// come or under way, when the next timed one starts and what it is, and how many reminders
/// are overdue.
public struct DaySummary: Equatable, Sendable {
    public let count: Int
    /// The start of the next timed event or the time of the next timed reminder; nil when none.
    public let next: Date?
    /// The title of that next one; nil when none.
    public let nextTitle: String?
    /// Open reminders past their due time, which are not today's.
    public let overdue: Int

    public init(count: Int, next: Date?, nextTitle: String? = nil, overdue: Int = 0) {
        self.count = count
        self.next = next
        self.nextTitle = nextTitle
        self.overdue = overdue
    }

    public static func make(events: [AgendaEvent], reminders: [AgendaReminder], at now: Date, calendar: Calendar) -> DaySummary {
        let list = DayList.make(events: events, reminders: reminders, at: now, calendar: calendar)
        let starts: [(date: Date, title: String)] = list.events.filter { !$0.isAllDay && $0.start > now }.map { ($0.start, $0.title) }
            + list.dueToday.compactMap { reminder in
                guard reminder.dueHasTime, let due = reminder.due, due > now else { return nil }
                return (due, reminder.title)
            }
        let next = starts.min { $0.date < $1.date }
        return DaySummary(
            count: list.events.count + list.dueToday.count, next: next?.date, nextTitle: next?.title,
            overdue: list.overdue.count)
    }
}

/// Today's things as the calendar widget lists them: the events not over yet, the open
/// reminders due today, and apart from them the overdue ones, oldest first. Reminders due
/// later or without a date are not today's and are left out.
public struct DayList: Equatable, Sendable {
    public let events: [AgendaEvent]
    public let dueToday: [AgendaReminder]
    public let overdue: [AgendaReminder]

    public static func make(events: [AgendaEvent], reminders: [AgendaReminder], at now: Date, calendar: Calendar) -> DayList {
        let today = events.filter { event in
            event.isAllDay ? calendar.isDate(event.start, inSameDayAs: now) : event.end > now && calendar.isDate(event.start, inSameDayAs: now)
        }
        let open = reminders.filter { !$0.isCompleted }
        let overdue = open.filter { $0.isOverdue(at: now, calendar: calendar) }
            .sorted { ($0.due ?? .distantPast, $0.id) < ($1.due ?? .distantPast, $1.id) }
        let dueToday = open.filter { reminder in
            guard let due = reminder.due, !reminder.isOverdue(at: now, calendar: calendar) else { return false }
            return calendar.isDate(due, inSameDayAs: now)
        }
        return DayList(events: today, dueToday: dueToday, overdue: overdue)
    }
}
