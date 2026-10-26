import Foundation

/// How urgent a reminder is, as the reminders app shows it.
public enum ReminderPriority: String, CaseIterable, Sendable {
    case none, low, medium, high

    /// From the number the system keeps: 0 for none, 1 to 4 high, 5 medium, 6 to 9 low.
    public init(systemValue: Int) {
        switch systemValue {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var systemValue: Int {
        switch self {
        case .none: 0
        case .low: 9
        case .medium: 5
        case .high: 1
        }
    }
}

/// How often a reminder comes back.
public enum ReminderRepeat: String, CaseIterable, Sendable {
    case never, daily, weekly, monthly, yearly
}

/// Everything about one reminder that can be changed from the notch.
public struct ReminderDetail: Equatable, Identifiable, Sendable {
    /// How long before it is due a reminder can alert: not early at all, or so many minutes.
    public static let alertChoices: [Int?] = [nil, 5, 15, 30, 60, 1_440]
    /// How long the work of a reminder can be said to take, in minutes: no estimate, half
    /// an hour, or one to eight hours.
    public static let estimateChoices: [Int?] = [nil, 30, 60, 120, 180, 240, 480]

    public let id: String
    public var title: String
    public var notes: String
    /// When it is due; with `dueHasTime` false, the start of the day it is due on.
    public var due: Date?
    public var dueHasTime: Bool
    public var repeats: ReminderRepeat
    /// Minutes before the due time to alert as well; nil for no early alert.
    public var alertMinutes: Int?
    public var priority: ReminderPriority
    /// The list the reminder is in.
    public var listID: String
    /// How many minutes the work is thought to take, ending at the due time; nil for no
    /// estimate. Kept by the notch itself: the system's reminders have no place for it.
    public var estimateMinutes: Int?

    public init(
        id: String, title: String, notes: String, due: Date?, dueHasTime: Bool, repeats: ReminderRepeat,
        alertMinutes: Int?, priority: ReminderPriority, listID: String, estimateMinutes: Int? = nil
    ) {
        self.estimateMinutes = estimateMinutes
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.dueHasTime = dueHasTime
        self.repeats = repeats
        self.alertMinutes = alertMinutes
        self.priority = priority
        self.listID = listID
    }

    /// A reminder must have a name.
    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The reminder as it is saved: texts trimmed, and nothing kept that its due date cannot
    /// carry. Without a day there is nothing to repeat from; without an hour, nothing to be
    /// early for and no end for the work to be drawn to.
    public var normalized: ReminderDetail {
        var saved = self
        saved.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if due == nil {
            saved.dueHasTime = false
            saved.repeats = .never
        }
        if !saved.dueHasTime {
            saved.alertMinutes = nil
            saved.estimateMinutes = nil
        }
        return saved
    }

    /// Moves the reminder to a day, keeping its hour if it has one. One with no day yet gets
    /// an hour too, so that what needs one (an estimate, an early alert) can be chosen at
    /// once; one due at no hour stays so.
    /// - Parameter newMinutesOfDay: the hour, as minutes of the day, for a reminder with no day yet.
    public mutating func setDay(_ day: Date, newMinutesOfDay: Int, calendar: Calendar) {
        let start = calendar.startOfDay(for: day)
        guard let due else {
            self.due = calendar.date(byAdding: .minute, value: newMinutesOfDay, to: start) ?? start
            dueHasTime = true
            return
        }
        guard dueHasTime else {
            self.due = start
            return
        }
        let minutes = calendar.component(.hour, from: due) * 60 + calendar.component(.minute, from: due)
        self.due = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    /// Gives the reminder an hour, on its own day or, having none, on today.
    public mutating func setMinutesOfDay(_ minutes: Int, today: Date, calendar: Calendar) {
        let start = calendar.startOfDay(for: due ?? today)
        due = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
        dueHasTime = true
    }
    /// What differs from the reminder as it was read. Only these are written back, so that
    /// what the notch does not show of a reminder (a repeat every other week, an alert at
    /// a place) is not lost by changing its name.
    public func changes(from original: ReminderDetail) -> Set<ReminderChange> {
        var changed: Set<ReminderChange> = []
        if title != original.title { changed.insert(.title) }
        if notes != original.notes { changed.insert(.notes) }
        if due != original.due || dueHasTime != original.dueHasTime { changed.insert(.due) }
        if repeats != original.repeats { changed.insert(.repeats) }
        if alertMinutes != original.alertMinutes { changed.insert(.alert) }
        if priority != original.priority { changed.insert(.priority) }
        if listID != original.listID { changed.insert(.list) }
        if estimateMinutes != original.estimateMinutes { changed.insert(.estimate) }
        return changed
    }

    /// How many minutes before it is due a reminder alerts, read from its alarms: those set
    /// at a moment and those set as a distance from the due time, in seconds. Of several
    /// early ones, the one nearest the due time; nil when none is early.
    public static func earlyMinutes(due: Date?, alarmDates: [Date], offsets: [TimeInterval]) -> Int? {
        let leads = alarmDates.compactMap { date in due.map { $0.timeIntervalSince(date) } } + offsets.map { -$0 }
        return leads.map { Int(($0 / 60).rounded()) }.filter { $0 > 0 }.min()
    }

    /// Makes the reminder due on a whole day, at no hour: the day it has, or today.
    public mutating func setAllDay(today: Date, calendar: Calendar) {
        due = calendar.startOfDay(for: due ?? today)
        dueHasTime = false
    }
}

/// One of the things about a reminder that can be changed from the notch.
public enum ReminderChange: CaseIterable, Sendable {
    case title, notes, due, repeats, alert, priority, list, estimate
}

/// A list reminders are kept in.
public struct ReminderList: Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    /// The list's colour as 0xRRGGBB.
    public var tint: UInt32?

    public init(id: String, name: String, tint: UInt32? = nil) {
        self.id = id
        self.name = name
        self.tint = tint
    }
}

/// The room a reminder being edited takes on the calendar page.
public enum ReminderEditorLayout {
    /// The height of the title, of the notes, of a row of chips and of the buttons.
    public static let titleHeight: Double = 20
    public static let notesHeight: Double = 18
    public static let chipsHeight: Double = 24
    public static let buttonsHeight: Double = 26
    /// Between two rows of the card, and round it: inside, top and bottom together, and outside.
    public static let spacing: Double = 4
    public static let padding: Double = 12
    public static let margin: Double = 4

    /// The height of the card with its margins; a second row of chips while the choices
    /// of one are on show.
    public static func height(isChoosing: Bool) -> Double {
        let rows = [titleHeight, notesHeight, chipsHeight, buttonsHeight] + (isChoosing ? [chipsHeight] : [])
        return rows.reduce(0, +) + Double(rows.count - 1) * spacing + padding + margin
    }
}
