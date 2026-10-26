import Foundation

/// The one thing of today a small tile has room for: the meeting under way or coming next,
/// else an all-day event, else the first open reminder.
public enum NextUp: Equatable, Sendable {
    case event(title: String, timing: Timing)
    case reminder(title: String)

    public enum Timing: Equatable, Sendable {
        case now
        /// Starts within the hour, in this many minutes (rounded up).
        case inMinutes(Int)
        case at(Date)
        case allDay
    }

    public static func find(events: [AgendaEvent], reminders: [AgendaReminder], at now: Date) -> NextUp? {
        let timed = events
            .filter { !$0.isAllDay && $0.end > now }
            .sorted { $0.start < $1.start }
        if let meeting = timed.first {
            let wait = meeting.start.timeIntervalSince(now)
            if wait <= 0 { return .event(title: meeting.title, timing: .now) }
            if wait < 3600 { return .event(title: meeting.title, timing: .inMinutes(Int((wait / 60).rounded(.up)))) }
            return .event(title: meeting.title, timing: .at(meeting.start))
        }
        if let allDay = events.first(where: \.isAllDay) {
            return .event(title: allDay.title, timing: .allDay)
        }
        return reminders.first.map { .reminder(title: $0.title) }
    }
}
