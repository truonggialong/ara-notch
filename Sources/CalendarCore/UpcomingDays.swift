import Foundation

/// One thing on a day ahead: an event, or an open reminder due that day.
public struct UpcomingItem: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case event, reminder
    }

    public let kind: Kind
    /// The identifier of the event or reminder it stands for.
    public let sourceID: String
    public let title: String
    /// When it starts or is due; nil for one that takes the whole day, or has no hour on it.
    public let time: Date?
    /// The calendar's colour as 0xRRGGBB, for an event that has one.
    public let tint: UInt32?

    /// An event and a reminder may share an identifier; the kind tells them apart.
    public var id: String { "\(kind.rawValue):\(sourceID)" }
}

/// A day ahead with what is on it.
public struct UpcomingDay: Equatable, Identifiable, Sendable {
    /// The day, at its start.
    public let day: Date
    public let items: [UpcomingItem]

    public var id: Date { day }
}

/// What is on the next few days, for the calendar page's tallest size.
public enum UpcomingDays {
    /// How many days after today are listed.
    public static let dayCount = 3

    /// The days after today that have something on them, each with its events and open
    /// reminders: those for the whole day first, then the rest by time. An event over several
    /// days is on each of them, with its hour only on the first.
    public static func days(
        events: [AgendaEvent], reminders: [AgendaReminder], now: Date, calendar: Calendar, count: Int = dayCount
    ) -> [UpcomingDay] {
        let today = calendar.startOfDay(for: now)
        return (1...max(count, 1)).compactMap { offset -> UpcomingDay? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return nil }
            let onDay = events.filter { $0.start < end && $0.end > start }.map {
                UpcomingItem(
                    kind: .event, sourceID: $0.id, title: $0.title,
                    time: $0.isAllDay || $0.start < start ? nil : $0.start, tint: $0.tint)
            }
            let due = reminders.filter { reminder in
                guard !reminder.isCompleted, let due = reminder.due else { return false }
                return due >= start && due < end
            }.map {
                UpcomingItem(
                    kind: .reminder, sourceID: $0.id, title: $0.title, time: $0.dueHasTime ? $0.due : nil, tint: nil)
            }
            let items = (onDay + due).sorted { first, second in
                switch (first.time, second.time) {
                case (nil, .some): return true
                case (.some, nil): return false
                case let (.some(a), .some(b)) where a != b: return a < b
                default:
                    if first.kind != second.kind { return first.kind == .event }
                    return (first.title, first.sourceID) < (second.title, second.sourceID)
                }
            }
            return items.isEmpty ? nil : UpcomingDay(day: start, items: items)
        }
    }
}
