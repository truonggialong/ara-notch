import Foundation

/// One day laid out as a chart: a row for each event and reminder, placed across the hours.
public struct DayTimeline: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public enum Kind: Equatable, Sendable {
            case event, reminder
        }

        public let id: String
        public let kind: Kind
        public let title: String
        /// Where the row begins, in hours of the day; nil for a row with no time on this day.
        public var start: Double?
        /// Where it ends; nil for a reminder, which is a moment, and for a row with no time.
        public var end: Double?
        /// For a reminder with an estimate: where its work begins, so many hours before the
        /// moment it is due at. The work is drawn from here to `start`.
        public var workStart: Double?
        public var isAllDay = false
        /// A reminder whose time has passed.
        public var isOverdue = false
        /// A reminder finished on this day: listed after the open ones, with no place across the hours.
        public var isDone = false
        /// The calendar's colour as 0xRRGGBB, for an event that has one.
        public var tint: UInt32?
    }

    /// The fewest hours shown across, so that a single short meeting is not stretched over the chart.
    public static let minimumSpan = 8
    /// The hours shown on a day with nothing at a set time.
    public static let workingHours = 8...18

    public let rows: [Row]
    /// The whole hours the chart runs from and to.
    public let firstHour: Int
    public let lastHour: Int

    /// - Parameters:
    ///   - events: any events; those not touching `day` are left out.
    ///   - reminders: open reminders; those due on `day` are shown and, when `day` is today,
    ///     also the overdue ones and those without a date.
    ///   - completed: finished reminders; those finished on `day` are listed, the latest first.
    ///   - estimates: minutes of work by reminder; the due time is the work's deadline.
    public init(
        day: Date, events: [AgendaEvent], reminders: [AgendaReminder], completed: [AgendaReminder] = [],
        estimates: [String: Int] = [:], now: Date, calendar: Calendar
    ) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let isToday = calendar.isDate(day, inSameDayAs: now)
        func hour(_ date: Date) -> Double {
            min(max(date.timeIntervalSince(start) / 3_600, 0), 24)
        }

        let touching = events.filter { $0.start < end && $0.end > start }
        let allDay = touching.filter(\.isAllDay).map {
            Row(id: $0.id, kind: .event, title: $0.title, isAllDay: true, tint: $0.tint)
        }
        let timed = touching.filter { !$0.isAllDay }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.map {
            Row(id: $0.id, kind: .event, title: $0.title, start: hour($0.start), end: hour($0.end), tint: $0.tint)
        }

        let open = reminders.filter { !$0.isCompleted }
        func isOnDay(_ reminder: AgendaReminder) -> Bool {
            guard let due = reminder.due else { return false }
            return due >= start && due < end
        }
        let atATime = open.filter { isOnDay($0) && $0.dueHasTime }
            .sorted { ($0.due ?? start, $0.id) < ($1.due ?? start, $1.id) }
            .map { reminder in
                let due = hour(reminder.due ?? start)
                return Row(
                    id: reminder.id, kind: .reminder, title: reminder.title, start: due,
                    // Work that would begin the day before begins with the day.
                    workStart: estimates[reminder.id].map { max(due - Double($0) / 60, 0) },
                    isOverdue: reminder.isOverdue(at: now, calendar: calendar))
            }
        let overdue = !isToday ? [] : open.filter { !isOnDay($0) && $0.isOverdue(at: now, calendar: calendar) }
            .sorted { ($0.due ?? start, $0.id) < ($1.due ?? start, $1.id) }
            .map { Row(id: $0.id, kind: .reminder, title: $0.title, isOverdue: true) }
        let onTheDay = open.filter { isOnDay($0) && !$0.dueHasTime }.sorted { $0.id < $1.id }
            .map { Row(id: $0.id, kind: .reminder, title: $0.title) }
        let undated = !isToday ? [] : open.filter { $0.due == nil }.sorted { $0.id < $1.id }
            .map { Row(id: $0.id, kind: .reminder, title: $0.title) }

        let finished = completed
            .filter { reminder in reminder.completedAt.map { $0 >= start && $0 < end } ?? false }
            .sorted { ($0.completedAt ?? start, $0.id) > ($1.completedAt ?? start, $1.id) }
            .map { Row(id: $0.id, kind: .reminder, title: $0.title, isDone: true) }

        rows = allDay + timed + atATime + overdue + onTheDay + undated + finished

        let starts = (timed + atATime).compactMap { $0.workStart ?? $0.start }
        let ends = timed.compactMap(\.end) + atATime.compactMap(\.start)
        guard let earliest = starts.min(), let latest = ends.max() else {
            firstHour = Self.workingHours.lowerBound
            lastHour = Self.workingHours.upperBound
            return
        }
        var first = max(Int(earliest.rounded(.down)) - 1, 0)
        var last = min(Int(latest.rounded(.up)) + 1, 24)
        if last - first < Self.minimumSpan {
            last = min(first + Self.minimumSpan, 24)
            first = max(last - Self.minimumSpan, 0)
        }
        firstHour = first
        lastHour = last
    }

    /// The day as it would be if a reminder being changed were saved now, so that a time or
    /// an estimate shows on the chart as it is chosen. A day chosen that would take the
    /// reminder off this chart is not shown: its row, with the editor under it, stays put.
    /// - Parameter detail: the reminder as it stands in its editor; nil when none is open.
    public static func previewing(
        _ detail: ReminderDetail?, day: Date, events: [AgendaEvent], reminders: [AgendaReminder],
        completed: [AgendaReminder] = [], estimates: [String: Int], now: Date, calendar: Calendar
    ) -> DayTimeline {
        func timeline(_ reminders: [AgendaReminder], _ estimates: [String: Int]) -> DayTimeline {
            DayTimeline(
                day: day, events: events, reminders: reminders, completed: completed, estimates: estimates, now: now,
                calendar: calendar)
        }
        guard let detail = detail?.normalized, let index = reminders.firstIndex(where: { $0.id == detail.id }) else {
            return timeline(reminders, estimates)
        }
        var chosen = estimates
        chosen[detail.id] = detail.estimateMinutes
        var changed = reminders
        changed[index].due = detail.due
        changed[index].dueHasTime = detail.dueHasTime
        if !detail.title.isEmpty {
            changed[index].title = detail.title
        }
        let preview = timeline(changed, chosen)
        return preview.rows.contains { $0.id == detail.id } ? preview : timeline(reminders, chosen)
    }

    /// The rows that have a place across the hours: events, and reminders due at a time.
    public var timedRows: [Row] {
        rows.filter { $0.isAllDay || $0.start != nil }
    }

    /// Reminders whose day has passed. They have no place across today's hours.
    public var overdueRows: [Row] {
        rows.filter { !$0.isAllDay && $0.start == nil && $0.isOverdue && !$0.isDone }
    }

    /// Reminders with no time: due on the day at no hour, or with no date at all.
    public var untimedRows: [Row] {
        rows.filter { !$0.isAllDay && $0.start == nil && !$0.isOverdue && !$0.isDone }
    }

    /// Reminders finished on the day, the latest first.
    public var doneRows: [Row] {
        rows.filter(\.isDone)
    }

    /// The lines kept for the chart on a day with nothing at a set hour: the hours stay on
    /// show over this much empty room, so the page is still a chart.
    public static let emptyChartLines = 2

    /// How many lines the chart takes: one for each timed row (or the empty room when there
    /// is none), and for each of the groups with no place across the hours a heading and its
    /// rows set two abreast.
    public var lineCount: Int {
        func lines(_ group: [Row]) -> Int {
            group.isEmpty ? 0 : 1 + (group.count + 1) / 2
        }
        return max(timedRows.count, Self.emptyChartLines) + lines(overdueRows) + lines(untimedRows) + lines(doneRows)
    }

    /// Where an hour of the day falls across the chart, from 0 at its left edge to 1 at its right.
    public func position(ofHour hour: Double) -> Double {
        let span = Double(max(lastHour - firstHour, 1))
        return min(max((hour - Double(firstHour)) / span, 0), 1)
    }

    /// A moment as hours of its day.
    public func hourOf(_ date: Date, calendar: Calendar = .current) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date)) / 3_600
    }
}

/// How much room the calendar page takes: as tall as what it shows needs, on either side.
/// The notch grows downwards for it, never sideways, and cuts it to what the screen allows.
public enum CalendarPageHeight {
    /// The least height of sheet: what the month on the left needs, with the line under it.
    /// A little more than the usual sheet of 200.
    public static let minimumSheetHeight: Double = 232
    /// The height of sheet for a picker: a month of six weeks with two rows of quick days
    /// under it.
    public static let pickerSheetHeight: Double = 268
    /// The height of one row of the day's chart.
    public static let rowHeight: Double = 22
    /// What stands above the rows: the tab row, the page's margins, the day's heading and the hours.
    static let chromeHeight: Double = 104

    /// The room between the month's line and the list of the next days.
    public static let upcomingTop: Double = 8
    /// The height of the list's heading, of a line of it, and of a day's name with the room above it.
    public static let upcomingLine: Double = 16
    public static let upcomingDayTitle: Double = 20

    /// The height of sheet to ask the notch for.
    /// - Parameters:
    ///   - rows: the lines of the day's chart.
    ///   - extra: room for what stands among the rows without being one, in points.
    ///   - upcoming: the next days listed under the month.
    ///   - isPicking: a month and a clock stand in place of the rows, on a page of their own height.
    public static func sheetHeight(
        rows: Int, extra: Double = 0, upcoming: [UpcomingDay] = [], isPicking: Bool = false
    ) -> Double {
        if isPicking {
            return pickerSheetHeight
        }
        let day = chromeHeight + Double(rows) * rowHeight + extra
        return max(minimumSheetHeight + upcomingHeight(upcoming), day)
    }

    /// The height of the list of the next days under the month: its heading, then each day's
    /// name and a line for each thing on it, or one line saying there is nothing.
    public static func upcomingHeight(_ days: [UpcomingDay]) -> Double {
        let lines = days.isEmpty
            ? upcomingLine
            : days.map { upcomingDayTitle + Double($0.items.count) * upcomingLine }.reduce(0, +)
        return upcomingTop + upcomingLine + lines
    }
}
