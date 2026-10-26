import AppKit
import CalendarCore
import EventKit

/// Whether the app may read the user's events or reminders.
enum AgendaAccess: Equatable {
    case undetermined
    case granted
    case denied
}

/// Reads events and reminders from the system's calendar store. Nothing is read, and macOS
/// asks nothing, until access was requested and given.
@MainActor
final class AgendaSource {
    private let store = EKEventStore()

    static func access(to type: EKEntityType) -> AgendaAccess {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    /// Makes macOS ask the user. The answer arrives on the main actor.
    func requestAccess(to type: EKEntityType, completion: @escaping @MainActor (Bool) -> Void) {
        let handler: @Sendable (Bool, Error?) -> Void = { granted, _ in
            Task { @MainActor in completion(granted) }
        }
        if type == .reminder {
            store.requestFullAccessToReminders(completion: handler)
        } else {
            store.requestFullAccessToEvents(completion: handler)
        }
    }

    /// Calls back on the main actor whenever a calendar or reminder changes.
    func observeChanges(_ action: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
    }

    /// Events overlapping the period, without cancelled ones and those the user declined.
    func events(from start: Date, to end: Date) -> [AgendaEvent] {
        guard Self.access(to: .event) == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled else { return nil }
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            guard !declined else { return nil }
            // Every occurrence of a repeating event shares one identifier; the start tells them apart.
            let id = "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)"
            var item = AgendaEvent(
                id: id, title: event.title ?? "", start: event.startDate, end: event.endDate,
                isAllDay: event.isAllDay, calendarName: event.calendar?.title ?? "", location: event.location,
                joinURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]),
                tint: event.calendar.flatMap { Self.tint(of: $0.color) })
            item.itemID = event.calendarItemIdentifier
            item.isRepeating = event.hasRecurrenceRules
            return item
        }
    }

    /// Reminders not yet completed. The answer arrives on the main actor.
    func openReminders(completion: @escaping @MainActor ([AgendaReminder]) -> Void) {
        guard Self.access(to: .reminder) == .granted else {
            completion([])
            return
        }
        Self.fetchOpenReminders(from: store, completion: completion)
    }

    /// Outside the main actor on purpose: EventKit answers on a queue of its own, and a closure
    /// written inside a main-actor method would be checked for the main thread there and trap.
    private nonisolated static func fetchOpenReminders(
        from store: EKEventStore, completion: @escaping @MainActor ([AgendaReminder]) -> Void
    ) {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { found in
            let calendar = Calendar.current
            let reminders = (found ?? []).map { reminder in
                let components = reminder.dueDateComponents
                return AgendaReminder(
                    id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                    due: components.flatMap { calendar.date(from: $0) },
                    dueHasTime: components?.hour != nil,
                    isCompleted: reminder.isCompleted, listName: reminder.calendar?.title ?? "")
            }
            Task { @MainActor in completion(reminders) }
        }
    }

    /// Reminders finished between two moments. The answer arrives on the main actor.
    func completedReminders(
        from start: Date, to end: Date, completion: @escaping @MainActor ([AgendaReminder]) -> Void
    ) {
        guard Self.access(to: .reminder) == .granted else {
            completion([])
            return
        }
        Self.fetchCompletedReminders(from: store, start: start, end: end, completion: completion)
    }

    /// Outside the main actor for the same reason as `fetchOpenReminders`.
    private nonisolated static func fetchCompletedReminders(
        from store: EKEventStore, start: Date, end: Date, completion: @escaping @MainActor ([AgendaReminder]) -> Void
    ) {
        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: start, ending: end, calendars: nil)
        store.fetchReminders(matching: predicate) { found in
            let calendar = Calendar.current
            let reminders = (found ?? []).map { reminder in
                let components = reminder.dueDateComponents
                return AgendaReminder(
                    id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                    due: components.flatMap { calendar.date(from: $0) },
                    dueHasTime: components?.hour != nil,
                    isCompleted: true, listName: reminder.calendar?.title ?? "",
                    completedAt: reminder.completionDate)
            }
            Task { @MainActor in completion(reminders) }
        }
    }

    /// Adds an event to the user's default calendar. Returns false without access to the
    /// calendars, without a calendar to write to, or when the save fails.
    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool) -> Bool {
        guard Self.access(to: .event) == .granted, let calendar = store.defaultCalendarForNewEvents else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        // An all-day event ends on its own day for the calendar store, not at the next midnight.
        event.endDate = isAllDay ? start : end
        event.isAllDay = isAllDay
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Adds a reminder with an alert at its due time to the user's default Reminders list.
    /// Returns false without access to Reminders, or when the save fails.
    /// - Parameter due: when to remind; nil makes a reminder without a time.
    func createReminder(title: String, notes: String?, due: Date?) -> Bool {
        guard Self.access(to: .reminder) == .granted, let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Makes a reminder and takes it away again at once; says whether both worked. For checking
    /// that reminders can really be written, without leaving anything in the user's list.
    func createAndRemoveReminder(title: String, due: Date) -> Bool {
        guard Self.access(to: .reminder) == .granted, let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        reminder.addAlarm(EKAlarm(absoluteDate: due))
        do {
            try store.save(reminder, commit: true)
            try store.remove(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// The reminder to change, or what stands in the way of changing it.
    private func changeableReminder(id: String) -> Result<EKReminder, ReminderFailure> {
        let hasAccess = Self.access(to: .reminder) == .granted
        let reminder = hasAccess ? store.calendarItem(withIdentifier: id) as? EKReminder : nil
        if let failure = ReminderFailure.reason(
            hasAccess: hasAccess, exists: reminder != nil,
            isWritable: reminder?.calendar?.allowsContentModifications ?? false, systemMessage: nil) {
            return .failure(failure)
        }
        guard let reminder else { return .failure(.gone) }
        return .success(reminder)
    }

    /// Runs a write to the store; what the system said when it fails.
    private func commit(_ write: () throws -> Void) -> ReminderFailure? {
        do {
            try write()
            return nil
        } catch {
            return .system(error.localizedDescription)
        }
    }

    /// Marks a reminder as completed in the user's Reminders. Nil when done, otherwise why not.
    @discardableResult
    func completeReminder(id: String) -> ReminderFailure? {
        switch changeableReminder(id: id) {
        case .failure(let failure):
            return failure
        case .success(let reminder):
            reminder.isCompleted = true
            return commit { try store.save(reminder, commit: true) }
        }
    }

    /// Makes a finished reminder open again in the user's Reminders. Nil when done, otherwise why not.
    @discardableResult
    func reopenReminder(id: String) -> ReminderFailure? {
        switch changeableReminder(id: id) {
        case .failure(let failure):
            return failure
        case .success(let reminder):
            reminder.isCompleted = false
            return commit { try store.save(reminder, commit: true) }
        }
    }

    // MARK: - Changing a reminder

    /// Everything about a reminder that can be changed from the notch; nil when it is gone.
    func reminderDetail(id: String) -> ReminderDetail? {
        guard Self.access(to: .reminder) == .granted,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return nil }
        let components = reminder.dueDateComponents
        let repeats: ReminderRepeat = switch reminder.recurrenceRules?.first?.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        default: .never
        }
        let due = components.flatMap { Calendar.current.date(from: $0) }
        // An early alert is an alarm set some time before the due time; one at a place is not.
        let alarms = (reminder.alarms ?? []).filter { $0.structuredLocation == nil }
        let early = ReminderDetail.earlyMinutes(
            due: due, alarmDates: alarms.compactMap(\.absoluteDate),
            offsets: alarms.filter { $0.absoluteDate == nil }.map(\.relativeOffset))
        return ReminderDetail(
            id: id, title: reminder.title ?? "", notes: reminder.notes ?? "",
            due: due, dueHasTime: components?.hour != nil,
            repeats: repeats, alertMinutes: early, priority: ReminderPriority(systemValue: reminder.priority),
            listID: reminder.calendar?.calendarIdentifier ?? "")
    }

    /// The lists a reminder can be kept in.
    func reminderLists() -> [ReminderList] {
        guard Self.access(to: .reminder) == .granted else { return [] }
        return store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ReminderList(id: $0.calendarIdentifier, name: $0.title, tint: Self.tint(of: $0.color)) }
    }

    /// Writes back what was changed of a reminder, and nothing else: a repeat or an alert
    /// set up elsewhere in a way the notch does not show stays as it was unless that very
    /// thing was changed. Nil when saved, otherwise why not.
    func save(_ detail: ReminderDetail) -> ReminderFailure? {
        let reminder: EKReminder
        switch changeableReminder(id: detail.id) {
        case .failure(let failure):
            return failure
        case .success(let found):
            reminder = found
        }
        guard let original = reminderDetail(id: detail.id) else { return .gone }
        let detail = detail.normalized
        // An estimate is the notch's own; the system's reminder has no place for it.
        let changes = detail.changes(from: original.normalized).subtracting([.estimate])
        guard !changes.isEmpty else { return nil }

        if changes.contains(.title) {
            reminder.title = detail.title
        }
        if changes.contains(.notes) {
            reminder.notes = detail.notes.isEmpty ? nil : detail.notes
        }
        if changes.contains(.priority) {
            reminder.priority = detail.priority.systemValue
        }
        if changes.contains(.list), let list = store.calendar(withIdentifier: detail.listID), list.allowsContentModifications {
            reminder.calendar = list
        }
        if changes.contains(.due) {
            if let due = detail.due {
                let parts: Set<Calendar.Component> = detail.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
                reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
            } else {
                reminder.dueDateComponents = nil
            }
        }
        // The alerts that go with a time are set again from the due time; one that goes
        // with a place stays.
        if changes.contains(.due) || changes.contains(.alert) {
            for alarm in reminder.alarms ?? [] where alarm.structuredLocation == nil {
                reminder.removeAlarm(alarm)
            }
            if let due = detail.due, detail.dueHasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: due))
                if let minutes = detail.alertMinutes {
                    reminder.addAlarm(EKAlarm(absoluteDate: due.addingTimeInterval(TimeInterval(-minutes * 60))))
                }
            }
        }
        // Without a day there is nothing to repeat from, whatever the rule was.
        if changes.contains(.repeats) || detail.due == nil {
            for rule in reminder.recurrenceRules ?? [] {
                reminder.removeRecurrenceRule(rule)
            }
            let frequency: EKRecurrenceFrequency? = switch detail.repeats {
            case .never: nil
            case .daily: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            }
            if let frequency {
                reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil))
            }
        }
        return commit { try store.save(reminder, commit: true) }
    }

    /// Removes a reminder for good. Nil when removed, otherwise why not.
    func deleteReminder(id: String) -> ReminderFailure? {
        switch changeableReminder(id: id) {
        case .failure(let failure):
            return failure
        case .success(let reminder):
            return commit { try store.remove(reminder, commit: true) }
        }
    }

    private static func tint(of color: NSColor) -> UInt32? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = UInt32((rgb.redComponent * 255).rounded())
        let green = UInt32((rgb.greenComponent * 255).rounded())
        let blue = UInt32((rgb.blueComponent * 255).rounded())
        return red << 16 | green << 8 | blue
    }
}
