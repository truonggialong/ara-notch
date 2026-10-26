import AppKit
import CalendarCore
import Combine
import EventKit
import NotchShell
import SwiftUI

/// State the calendar page renders from.
@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var eventAccess = AgendaAccess.undetermined
    @Published var reminderAccess = AgendaAccess.undetermined
    @Published var agenda = Agenda(events: [], now: Date(), calendar: .current)
    @Published var reminders: [AgendaReminder] = []
    @Published var now = Date()

    var onRequestEvents: (() -> Void)?
    var onRequestReminders: (() -> Void)?
    var onOpenPrivacySettings: ((_ reminders: Bool) -> Void)?
    var onJoin: ((URL) -> Void)?
    var onComplete: ((AgendaReminder) -> Void)?
    var onAppear: (() -> Void)?
    /// The title of a reminder being typed on the page; nil while none is.
    @Published var reminderDraft: String?
    var onAddReminder: ((String) -> Void)?
    /// The day on show as a chart of its hours, and what each row stands for.
    @Published var timeline = DayTimeline(day: Date(), events: [], reminders: [], now: Date(), calendar: .current)
    var timelineEvents: [String: AgendaEvent] = [:]
    var timelineReminders: [String: AgendaReminder] = [:]
    /// The reminders finished on the day on show, by identifier: listed after the open ones.
    var doneReminders: [String: AgendaReminder] = [:]
    /// Make a finished reminder open again.
    var onReopen: ((AgendaReminder) -> Void)?
    /// The days of the month on show that have events, each at its start.
    @Published var markedDays: Set<Date> = []
    /// The next days with what is on them, listed under the month.
    @Published var upcoming: [UpcomingDay] = []
    /// The month calendar turned to another month.
    var onShowMonth: ((Date) -> Void)?
    /// Go to the next of the page's sizes.

    /// The reminder being changed on the page, with the changes made so far; nil while none is.
    @Published var editing: ReminderDetail?
    /// The chip of the editor whose choices are on show.
    @Published var editingField: ReminderField?
    /// The delete button was pressed once and waits to be pressed again.
    @Published var confirmsDelete = false
    /// The lists a reminder can be moved to.
    @Published var reminderLists: [ReminderList] = []
    /// Open or close the editor of a reminder.
    var onEditReminder: ((AgendaReminder) -> Void)?
    var onSaveEditing: (() -> Void)?
    var onCancelEditing: (() -> Void)?
    var onDeleteEditing: (() -> Void)?

    /// When the reminder being typed is due; nil for one without a day.
    @Published var reminderDue: Date?
    /// What the page shows in place of its lists while a day or a time is being chosen.
    @Published var picker: CalendarPicker?
    /// Titles used before, offered again for a click.
    /// The row for typing a reminder has just appeared.
    var onBeginReminder: (() -> Void)?

    /// The day chosen in the week strip, at its start; nil while the page shows today.
    @Published var selectedDay: Date?
    /// The chosen day's events, when it is not today.
    @Published var dayEvents: [AgendaEvent] = []
    /// An event being typed for the day shown; nil while none is.
    @Published var eventDraft: EventDraft?
    /// A notice shown at the foot of the open page, where what it is about was done: the
    /// one that takes back a reminder just ticked off, or the one that says why a change
    /// did not go through. A click on it does what it offers, or puts it away.
    @Published var pageNotice: AraSign?
    var onPageNotice: (() -> Void)?
    var onSelectDay: ((Date) -> Void)?
    var onOpenEvent: ((AgendaEvent) -> Void)?
    var onOpenReminder: ((AgendaReminder) -> Void)?
    /// Open the row for typing an event.
    var onBeginEvent: (() -> Void)?
    var onAddEvent: ((EventDraft) -> Void)?
}

/// The parts of a reminder chosen from a row of chips.
enum ReminderField: Equatable {
    case repeats, alert, priority, list, estimate
}

/// What is being chosen on the calendar page's picker.
enum CalendarPicker: Equatable {
    /// When the reminder being changed is due.
    case editing
    /// A day to show.
    case day
    /// The day and the start of the event being written.
    case event
    /// When the reminder being written is due.
    case reminder
}

/// Shows today's events and open reminders on the notch, and announces a meeting shortly
/// before it starts. Reads the user's calendars only after they allowed it from the page.
@MainActor
public final class CalendarController {
    private static let activityID = "calendar.meeting"

    private let settings: CalendarSettings
    private let notch: NotchController
    private let viewModel = CalendarViewModel()
    /// Made on first use, so an app that never shows the calendar never touches the store.
    private lazy var source = AgendaSource()
    private var planner: MeetingAlertPlanner
    private var events: [AgendaEvent] = []
    private var allReminders: [AgendaReminder] = []
    /// The events of the days after today, listed under the month.
    private var upcomingEvents: [AgendaEvent] = []
    /// Reminders finished on the day on show, which the page lists.
    private var completedReminders: [AgendaReminder] = []
    /// What was changed about made-up reminders during an automated check.
    private var simulatedDetails: [String: ReminderDetail] = [:]
    /// The estimates of made-up reminders, which are not written among the real ones.
    private var simulatedEstimates: [String: Int] = [:]
    /// One timer to the next moment something changes; an idle calendar has none running.
    private var wakeTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    /// Showing made-up data for an automated check; the real calendars are left alone.
    private var isSimulated = false

    public init(settings: CalendarSettings, notch: NotchController) {
        self.settings = settings
        self.notch = notch
        planner = MeetingAlertPlanner(leadMinutes: settings.leadMinutes)
        viewModel.onRequestEvents = { [weak self] in self?.requestAccess(to: .event) }
        viewModel.onRequestReminders = { [weak self] in self?.requestAccess(to: .reminder) }
        viewModel.onOpenPrivacySettings = { reminders in
            let pane = reminders ? "Privacy_Reminders" : "Privacy_Calendars"
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(url)
            }
        }
        viewModel.onJoin = { [weak notch] url in
            NSWorkspace.shared.open(url)
            notch?.close()
        }
        viewModel.onComplete = { [weak self] reminder in self?.complete(reminder) }
        viewModel.onAddReminder = { [weak self] title in self?.addReminder(titled: title) }
        viewModel.onBeginReminder = { [weak self] in self?.notch.focusTextField() }
        viewModel.onSelectDay = { [weak self] day in self?.select(day) }
        viewModel.onOpenEvent = { [weak notch] event in
            // An event made up for an automated check is not in the calendar app.
            guard let itemID = event.itemID,
                  let url = CalendarLinks.event(itemID: itemID, start: event.start, isRepeating: event.isRepeating)
            else { return }
            NSWorkspace.shared.open(url)
            notch?.close()
        }
        viewModel.onOpenReminder = { [weak self] reminder in
            // A made-up reminder of an automated check is not in the reminders app.
            guard let self, !self.isSimulated, let url = CalendarLinks.reminder(id: reminder.id) else { return }
            NSWorkspace.shared.open(url)
            self.notch.close()
        }
        viewModel.onBeginEvent = { [weak self] in self?.beginEvent() }
        viewModel.onAddEvent = { [weak self] draft in self?.addEvent(draft) }
        viewModel.onAppear = { [weak self] in self?.tick() }
        viewModel.onShowMonth = { [weak self] month in self?.markDays(ofMonthContaining: month) }
        // The page is as tall as what it shows needs: the rows of the day and a row being
        // written on the right, the month and the next days on the left.
        Publishers.CombineLatest4(
            viewModel.$timeline.map(\.lineCount), viewModel.$eventDraft.map { $0 != nil },
            viewModel.$reminderDraft.map { $0 != nil }, viewModel.$upcoming
        )
        .combineLatest(
            viewModel.$editing.map { $0 != nil }, viewModel.$editingField.map { $0 != nil },
            viewModel.$picker.map { $0 != nil }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] page, isEditing, isChoosing, isPicking in
            let (rows, hasEvent, hasReminder, upcoming) = page
            // A row being written takes its own line; a reminder being changed, the room of its editor.
            let drafts = (hasEvent ? 1 : 0) + (hasReminder ? 1 : 0)
            let height = CalendarPageHeight.sheetHeight(
                rows: rows + drafts, extra: isEditing ? ReminderEditorLayout.height(isChoosing: isChoosing) : 0,
                upcoming: upcoming, isPicking: isPicking)
            self?.notch.setSheetHeight(CGFloat(height), forPage: "calendar")
        }
        .store(in: &cancellables)
        viewModel.onReopen = { [weak self] reminder in self?.reopen(reminder) }
        // While a day and a time are being chosen the notch stays, wherever the pointer
        // goes, until the picker's Done: the owner's rule, after it closed on them mid-choice.
        viewModel.$picker
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isPicking in self?.notch.setKeepsOpen(isPicking, forPage: "calendar") }
            .store(in: &cancellables)
        // The chart follows the editor: a time or an estimate chosen there is drawn at once.
        viewModel.$editing
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshTimeline() }
            .store(in: &cancellables)
        viewModel.onEditReminder = { [weak self] reminder in self?.toggleEditing(reminder) }
        viewModel.onSaveEditing = { [weak self] in self?.saveEditing() }
        viewModel.onCancelEditing = { [weak self] in self?.endEditing() }
        viewModel.onDeleteEditing = { [weak self] in self?.deleteEditing() }
    }

    /// Opens the page on one of its pickers, for automated checks.
    public func showPicker(named name: String) {
        // After the notch has opened: closing, which it starts from, puts the picker away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            switch name {
            case "event":
                self.beginEvent()
                self.viewModel.picker = .event
            case "reminder":
                self.viewModel.reminderDraft = ""
                self.viewModel.picker = .reminder
            default:
                self.viewModel.picker = .day
            }
        }
    }

    /// Today at a glance, as a tile of the overview page.
    public func makeOverviewTile() -> AnyView {
        AnyView(CalendarWidget(model: viewModel, settings: settings) { [weak notch] in
            notch?.selectPage(id: "calendar")
        })
    }


    public func makePage() -> NotchPage {
        NotchPage(
            id: "calendar", titleKey: "page.calendar.title", symbolName: "calendar", hue: .mustard
        ) { [viewModel, settings] in
            CalendarPageView(model: viewModel, settings: settings)
        }
    }

    /// The meeting notice, for Settings › Notices.
    public func makeSettingsSection() -> AnyView {
        AnyView(CalendarSettingsSection(settings: settings))
    }

    /// What the calendar page shows, for Settings › Notch pages.
    public func makePageSettings() -> AnyView {
        AnyView(CalendarPageSettings(settings: settings))
    }

    public func start() {
        // Settings changes take effect at once: a shorter lead time may make a meeting due now.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
        // The next time the notch opens, the page is back on today; unless an event was
        // being written for the chosen day, which then waits where it was.
        notch.isOpenPublisher
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.viewModel.picker = nil
                guard let self, self.viewModel.selectedDay != nil, self.viewModel.eventDraft == nil else { return }
                self.viewModel.selectedDay = nil
                self.viewModel.dayEvents = []
                self.reloadCompleted()
            }
            .store(in: &cancellables)
        guard !isSimulated else { return }
        observers.append(source.observeChanges { [weak self] in self?.reload() })
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        observers.append(wake)
        reload()
    }

    /// Fills the page with made-up events and reminders around the current time, for automated
    /// checks: one meeting running, one starting in four minutes, more later and tomorrow.
    private var pageNoticeTimer: Timer?
    private var pageNoticeID: String?

    /// In made-up data, the list that stands for one that cannot be changed.
    private static let simulatedReadOnlyList = "Nhà"

    public func simulate() {
        isSimulated = true
        let now = Date()
        func event(_ id: String, _ title: String, in minutes: Double, lasting: Double, tint: UInt32, link: String? = nil) -> AgendaEvent {
            let start = now.addingTimeInterval(minutes * 60)
            return AgendaEvent(
                id: id, title: title, start: start, end: start.addingTimeInterval(lasting * 60), isAllDay: false,
                calendarName: "Công việc", location: nil, joinURL: link.flatMap(URL.init(string:)), tint: tint)
        }
        let today = Calendar.current.startOfDay(for: now)
        events = [
            AgendaEvent(
                id: "birthday", title: "Sinh nhật Lan", start: today, end: today.addingTimeInterval(86_400),
                isAllDay: true, calendarName: "Sinh nhật", location: nil, tint: 0xFF9F0A),
            event("standup", "Họp nhóm sản phẩm", in: -20, lasting: 45, tint: 0x0A84FF),
            event("client", "Gọi khách hàng Hải Âu", in: 4, lasting: 30, tint: 0x30D158,
                  link: "https://meet.google.com/abc-defg-hij"),
            event("lunch", "Ăn trưa với Minh", in: 95, lasting: 60, tint: 0xFF375F),
            event("review", "Review thiết kế", in: 24 * 60 + 30, lasting: 60, tint: 0x0A84FF),
        ]
        allReminders = [
            AgendaReminder(
                id: "report", title: "Gửi báo cáo tuần", due: now.addingTimeInterval(-26 * 3600),
                isCompleted: false, listName: "Công việc"),
            AgendaReminder(
                id: "milk", title: "Mua sữa", due: today, dueHasTime: false, isCompleted: false, listName: "Nhà"),
            AgendaReminder(id: "book", title: "Đọc sách 20 trang", due: nil, isCompleted: false, listName: "Cá nhân"),
        ]
        viewModel.eventAccess = .granted
        viewModel.reminderAccess = .granted
        tick()
        markDays(ofMonthContaining: now)
    }

    /// Writes what the app can read, as counts only, for an automated check: no title leaves
    /// the calendar store.
    public func writeSummary(to file: URL) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func count(days: Int) -> Int {
            source.events(from: today, to: calendar.date(byAdding: .day, value: days, to: today) ?? today).count
        }
        let events = "events: \(AgendaSource.access(to: .event)), 2 days: \(count(days: 2)), 30 days: \(count(days: 30))"
        let access = AgendaSource.access(to: .reminder)
        source.openReminders { reminders in
            let shown = AgendaReminder.upcoming(reminders, now: Date(), calendar: calendar).count
            let text = "\(events)\nreminders: \(access), open: \(reminders.count), shown: \(shown)\n"
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Makes a macOS reminder, asking for access to Reminders first when that was never
    /// decided. The answer says whether the reminder was made.
    public func createReminder(
        title: String, notes: String?, due: Date, completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !isSimulated else {
            completion(false)
            return
        }
        switch AgendaSource.access(to: .reminder) {
        case .granted:
            completion(source.createReminder(title: title, notes: notes, due: due))
            reload()
        case .undetermined:
            source.requestAccess(to: .reminder) { [weak self] granted in
                guard let self, granted else {
                    completion(false)
                    return
                }
                completion(self.source.createReminder(title: title, notes: notes, due: due))
                self.reload()
            }
        case .denied:
            completion(false)
        }
    }

    /// Whether a reminder can really be written: makes one and removes it at once. For automated checks.
    /// Adds the reminder written on the page, due when its picker says, if it says.
    private func addReminder(titled title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing typed closes the row; otherwise it stays, empty, for the next reminder.
        guard !title.isEmpty else {
            viewModel.reminderDraft = nil
            viewModel.reminderDue = nil
            return
        }
        let due = viewModel.reminderDue
        viewModel.reminderDraft = ""
        viewModel.reminderDue = nil
        if isSimulated {
            allReminders.insert(
                AgendaReminder(id: UUID().uuidString, title: title, due: due, isCompleted: false, listName: ""), at: 0)
            viewModel.reminders = allReminders
            return
        }
        if source.createReminder(title: title, notes: nil, due: due) {
            AraHaptics.play(.tap)
        } else {
            NSSound.beep()
        }
        reload()
    }

    public func canWriteReminders() -> Bool {
        source.createAndRemoveReminder(title: "AraNotch", due: Date().addingTimeInterval(3600))
    }

    // MARK: - A chosen day, and new events

    /// Shows the day in the week strip; choosing today goes back to following the clock.
    private func select(_ day: Date) {
        // The editor belongs to a row of the day on show; with another day it has no place.
        endEditing()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        viewModel.eventDraft = nil
        if calendar.isDateInToday(start) {
            viewModel.selectedDay = nil
            viewModel.dayEvents = []
        } else {
            viewModel.selectedDay = start
            viewModel.dayEvents = eventsOn(start)
        }
        refreshTimeline()
        reloadCompleted()
        AraHaptics.play(.change)
    }

    private func eventsOn(_ day: Date) -> [AgendaEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let found = isSimulated ? events : source.events(from: start, to: end)
        return DayAgenda.events(on: start, from: found, calendar: calendar)
    }

    private func beginEvent() {
        let now = Date()
        let day = viewModel.selectedDay ?? Calendar.current.startOfDay(for: now)
        viewModel.eventDraft = EventDraft(
            title: "", day: day, startMinutes: EventDraft.defaultStartMinutes(on: day, now: now, calendar: .current))
        notch.focusTextField()
    }

    /// Puts the typed event in the user's default calendar. An event without a title closes the row.
    private func addEvent(_ draft: EventDraft) {
        guard let interval = draft.interval(calendar: .current) else {
            viewModel.eventDraft = nil
            return
        }
        viewModel.eventDraft = nil
        // The page goes to the day the event was put on, so it is seen there.
        if !Calendar.current.isDate(draft.day, inSameDayAs: viewModel.selectedDay ?? Date()) {
            select(draft.day)
        }
        if isSimulated {
            events.append(AgendaEvent(
                id: UUID().uuidString, title: draft.trimmedTitle, start: interval.start, end: interval.end,
                isAllDay: draft.isAllDay, calendarName: "", location: nil))
            refreshChosenDay()
            tick()
            return
        }
        if source.createEvent(title: draft.trimmedTitle, start: interval.start, end: interval.end, isAllDay: draft.isAllDay) {
            AraHaptics.play(.tap)
        } else {
            NSSound.beep()
        }
        reload()
    }

    private func refreshChosenDay() {
        if let day = viewModel.selectedDay {
            viewModel.dayEvents = eventsOn(day)
        }
        refreshTimeline()
        markDays(ofMonthContaining: viewModel.selectedDay ?? Date())
    }

    /// Lays the day on show out as a chart: its events and the reminders that belong to it.
    private func refreshTimeline() {
        let now = Date()
        let day = viewModel.selectedDay ?? Calendar.current.startOfDay(for: now)
        let dayEvents = eventsOn(day)
        // What is being chosen in a reminder's editor shows at once, before Done.
        let completed = completedReminders
        let timeline = DayTimeline.previewing(
            viewModel.editing, day: day, events: dayEvents, reminders: allReminders, completed: completed,
            estimates: estimates, now: now, calendar: .current)
        viewModel.doneReminders = Dictionary(completed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        viewModel.timelineEvents = Dictionary(dayEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        viewModel.timelineReminders = Dictionary(allReminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if timeline != viewModel.timeline {
            viewModel.timeline = timeline
        }
    }

    /// Finds the days of a month that have events, for the dots of the month calendar.
    private func markDays(ofMonthContaining date: Date) {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: date) else { return }
        let found = isSimulated ? events : source.events(from: month.start, to: month.end)
        var days: Set<Date> = []
        for event in found where event.start < month.end && event.end > month.start {
            var day = calendar.startOfDay(for: max(event.start, month.start))
            // An event that ends at midnight does not reach into the day that starts then.
            while day < min(event.end, month.end) {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        viewModel.markedDays = days
    }

    // MARK: - Access

    private func requestAccess(to type: EKEntityType) {
        guard !isSimulated else { return }
        source.requestAccess(to: type) { [weak self] _ in self?.reload() }
    }

    // MARK: - Reading

    /// Reads today's and tomorrow's events and the open reminders again.
    private func reload() {
        guard !isSimulated else { return }
        viewModel.eventAccess = AgendaSource.access(to: .event)
        viewModel.reminderAccess = AgendaSource.access(to: .reminder)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        events = source.events(from: today, to: calendar.date(byAdding: .day, value: 2, to: today) ?? today)
        reloadUpcoming()
        refreshChosenDay()
        tick()

        guard viewModel.reminderAccess == .granted else { return }
        source.openReminders { [weak self] reminders in
            self?.allReminders = reminders
            self?.tick()
        }
        reloadCompleted()
    }

    /// Reads the events of the next days.
    private func reloadUpcoming() {
        defer { refreshUpcoming() }
        guard !isSimulated else { return }
        guard viewModel.eventAccess == .granted else {
            upcomingEvents = []
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: 1, to: today),
              let end = calendar.date(byAdding: .day, value: UpcomingDays.dayCount + 1, to: today)
        else { return }
        upcomingEvents = source.events(from: start, to: end)
    }

    /// Lists what is on the next days.
    private func refreshUpcoming() {
        let upcoming = UpcomingDays.days(
            events: isSimulated ? events : upcomingEvents, reminders: allReminders, now: Date(), calendar: .current)
        if upcoming != viewModel.upcoming {
            viewModel.upcoming = upcoming
        }
    }

    /// Reads the reminders finished on the day on show.
    private func reloadCompleted() {
        // Made-up reminders finished during an automated check are kept as they are.
        guard !isSimulated else {
            refreshTimeline()
            return
        }
        let calendar = Calendar.current
        let day = viewModel.selectedDay ?? calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        source.completedReminders(from: day, to: end) { [weak self] reminders in
            guard let self, (self.viewModel.selectedDay ?? calendar.startOfDay(for: Date())) == day else { return }
            self.completedReminders = reminders
            self.refreshTimeline()
        }
    }

    /// Brings the page up to the current time, announces meetings that are due, and arranges
    /// to be called at the next moment something changes.
    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        viewModel.now = now
        viewModel.agenda = Agenda(events: events, now: now, calendar: calendar)
        viewModel.reminders = AgendaReminder.upcoming(allReminders, now: now, calendar: calendar)
        refreshUpcoming()
        // A reminder completed or removed elsewhere while it was being changed here.
        if let editing = viewModel.editing, !allReminders.contains(where: { $0.id == editing.id }) {
            endEditing()
        }
        refreshTimeline()

        planner.leadMinutes = settings.leadMinutes
        if settings.meetingAlerts {
            // Several meetings at once: the earliest is the one shown.
            if let meeting = planner.due(events: events, now: now).first {
                announce(meeting, now: now)
            }
        }
        scheduleWake(after: now)
    }

    private func scheduleWake(after now: Date) {
        wakeTimer?.invalidate()
        wakeTimer = nil
        let lead = TimeInterval(settings.leadMinutes * 60)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        let moments = events.flatMap { [$0.start.addingTimeInterval(-lead), $0.start, $0.end] }
            + allReminders.compactMap(\.due) + [tomorrow].compactMap { $0 }
        guard let next = moments.filter({ $0 > now }).min() else { return }

        // Half a second late, so the moment has surely passed when the timer fires.
        let timer = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A new day needs new events; within the day the ones read are still right.
                if self.isSimulated || Calendar.current.isDate(Date(), inSameDayAs: now) {
                    self.tick()
                } else {
                    self.reload()
                }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        wakeTimer = timer
    }

    private func announce(_ meeting: AgendaEvent, now: Date) {
        let minutes = String(
            format: L10n.string("calendar.alert.minutes"), MeetingAlertPlanner.minutesUntil(meeting, from: now))
        let title = meeting.title
        notch.present(NotchLiveActivity(
            id: Self.activityID, priority: 3, duration: 10, pageID: "calendar",
            sign: AraSign(
                tone: .attention, icon: .symbol("calendar"), mark: L10n.string("page.calendar.title"),
                rows: [AraSign.Row(title, detail: minutes, badge: .digits(Self.clock.string(from: meeting.start)))])))
    }

    /// "14:30": when a meeting starts, for its notice.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Reminders

    // MARK: - Changing a reminder on the page

    /// Opens the editor under a reminder's row, or closes it when it is that reminder's.
    private func toggleEditing(_ reminder: AgendaReminder) {
        guard viewModel.editing?.id != reminder.id else {
            endEditing()
            return
        }
        if isSimulated {
            let lists = Array(Set(allReminders.map(\.listName))).sorted()
            viewModel.reminderLists = lists.map { ReminderList(id: $0, name: $0) }
            viewModel.editing = simulatedDetails[reminder.id] ?? ReminderDetail(
                id: reminder.id, title: reminder.title, notes: "", due: reminder.due,
                dueHasTime: reminder.due != nil && reminder.dueHasTime, repeats: .never, alertMinutes: nil,
                priority: .none, listID: reminder.listName)
        } else {
            guard let detail = source.reminderDetail(id: reminder.id) else {
                NSSound.beep()
                reload()
                return
            }
            viewModel.reminderLists = source.reminderLists()
            viewModel.editing = detail
        }
        viewModel.editing?.estimateMinutes = estimates[reminder.id]
        viewModel.editingField = nil
        viewModel.confirmsDelete = false
        AraHaptics.play(.tap)
    }

    /// How long each reminder's work is thought to take, in minutes.
    private var estimates: [String: Int] {
        isSimulated ? simulatedEstimates : settings.estimates
    }

    private func setEstimate(_ minutes: Int?, for id: String) {
        guard estimates[id] != minutes else { return }
        if isSimulated {
            simulatedEstimates[id] = minutes
        } else {
            settings.estimates[id] = minutes
        }
    }

    private func endEditing() {
        viewModel.editing = nil
        viewModel.editingField = nil
        viewModel.confirmsDelete = false
        if viewModel.picker == .editing {
            viewModel.picker = nil
        }
    }

    /// Writes the changes to the reminder and closes its editor. A reminder with no name is not saved.
    private func saveEditing() {
        guard let detail = viewModel.editing?.normalized, detail.canSave else {
            NSSound.beep()
            return
        }
        endEditing()
        setEstimate(detail.estimateMinutes, for: detail.id)
        // The page shows the change at once, as it did while it was being chosen; the next
        // reading of the reminders confirms it, or puts back what could not be saved.
        if let index = allReminders.firstIndex(where: { $0.id == detail.id }) {
            allReminders[index].title = detail.title
            allReminders[index].due = detail.due
            allReminders[index].dueHasTime = detail.dueHasTime
        }
        if isSimulated {
            // Made-up data: the list "Nhà" stands for a shared list that cannot be changed,
            // so that the notice for a failed save can be seen.
            if detail.listID == Self.simulatedReadOnlyList {
                announce(.readOnly, doing: .save)
                viewModel.editing = detail
                return
            }
            simulatedDetails[detail.id] = detail
            if let index = allReminders.firstIndex(where: { $0.id == detail.id }) {
                allReminders[index].listName = detail.listID
            }
            tick()
            return
        }
        tick()
        if let failure = source.save(detail) {
            announce(failure, doing: .save)
            reload()
            // What was typed is not lost: the editor opens again with it, unless the
            // reminder itself is gone.
            if failure != .gone {
                viewModel.editing = detail
            }
        } else {
            AraHaptics.play(.tap)
            reload()
        }
    }

    /// Removes the reminder being changed, on the second press of the button.
    private func deleteEditing() {
        guard let detail = viewModel.editing else { return }
        guard viewModel.confirmsDelete else {
            viewModel.confirmsDelete = true
            return
        }
        endEditing()
        setEstimate(nil, for: detail.id)
        allReminders.removeAll { $0.id == detail.id }
        tick()
        guard !isSimulated else { return }
        if let failure = source.deleteReminder(id: detail.id) {
            announce(failure, doing: .delete)
        }
        reload()
    }

    private func complete(_ reminder: AgendaReminder) {
        AraHaptics.play(.change)
        // The row goes at once, to the finished ones; when the save fails, the next read
        // brings it back.
        allReminders.removeAll { $0.id == reminder.id }
        var done = reminder
        done.isCompleted = true
        done.completedAt = Date()
        completedReminders.removeAll { $0.id == reminder.id }
        completedReminders.append(done)
        if viewModel.editing?.id == reminder.id {
            endEditing()
        }
        tick()
        if !isSimulated, let failure = source.completeReminder(id: reminder.id) {
            announce(failure, doing: .complete)
            reload()
            return
        }
        announceDone(reminder)
    }

    /// Five seconds to take back a reminder ticked off by mistake: a click on the notice
    /// opens it again. It is a sign at the foot of the open page, where the tick was made,
    /// and drops out of the notch as usual if the notch closes before the time is up.
    private func announceDone(_ reminder: AgendaReminder) {
        let sign = AraSign(
            tone: .plain, icon: .symbol("checkmark.circle.fill"), mark: L10n.string("calendar.done.mark"),
            title: L10n.string("calendar.done.title"), subtitle: reminder.title,
            rows: [AraSign.Row(L10n.string("calendar.done.undo"))])
        showNotice(sign, id: "calendar.done", for: 5) { [weak self] in
            guard let self else { return }
            let reopened = self.completedReminders.first { $0.id == reminder.id } ?? reminder
            self.reopen(reopened)
        }
    }

    /// Shows a notice at the foot of the open page and, should the notch close before its
    /// time is up, as a sign out of the closed notch. A click on either does `action` and puts
    /// both away.
    private func showNotice(_ sign: AraSign, id: String, for seconds: TimeInterval, action: (@MainActor () -> Void)? = nil) {
        endPageNotice()
        let clicked: @MainActor () -> Void = { [weak self] in
            self?.endPageNotice()
            action?()
        }
        pageNoticeID = id
        viewModel.pageNotice = sign
        viewModel.onPageNotice = clicked
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endPageNotice() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pageNoticeTimer = timer
        notch.present(NotchLiveActivity(id: id, priority: 2, duration: seconds, sign: sign, onClick: clicked))
    }

    private func endPageNotice() {
        pageNoticeTimer?.invalidate()
        pageNoticeTimer = nil
        viewModel.pageNotice = nil
        viewModel.onPageNotice = nil
        if let id = pageNoticeID {
            notch.dismissActivity(id: id)
        }
        pageNoticeID = nil
    }

    private enum ReminderAction: String {
        case save, delete, complete, reopen
    }

    /// Says why a change to a reminder did not go through.
    private func announce(_ failure: ReminderFailure, doing action: ReminderAction) {
        let reason = switch failure {
        case .noAccess: L10n.string("calendar.failed.noAccess")
        case .gone: L10n.string("calendar.failed.gone")
        case .readOnly: L10n.string("calendar.failed.readOnly")
        case .system(let message): message
        }
        showNotice(
            AraSign(
                tone: .danger, icon: .symbol("exclamationmark.triangle.fill"), mark: L10n.string("calendar.done.mark"),
                title: L10n.string("calendar.failed.\(action.rawValue)"),
                rows: [AraSign.Row(reason)]),
            id: "calendar.failed", for: 6)
    }

    /// Makes a finished reminder open again, as a click on its tick does in the reminders app.
    private func reopen(_ reminder: AgendaReminder) {
        AraHaptics.play(.change)
        completedReminders.removeAll { $0.id == reminder.id }
        var open = reminder
        open.isCompleted = false
        open.completedAt = nil
        allReminders.removeAll { $0.id == reminder.id }
        allReminders.append(open)
        tick()
        guard !isSimulated else { return }
        if let failure = source.reopenReminder(id: reminder.id) {
            announce(failure, doing: .reopen)
        }
        reload()
    }
}
