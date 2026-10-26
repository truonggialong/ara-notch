import Foundation

/// A calendar event as the notch shows it.
public struct AgendaEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarName: String
    public var location: String?
    /// A video call link found in the event, if any.
    public var joinURL: URL?
    /// The calendar's colour as 0xRRGGBB.
    public var tint: UInt32?
    /// What the system calls the calendar item, for opening it in the calendar app; nil for
    /// an event that is not in the user's calendars.
    public var itemID: String?
    public var isRepeating = false

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool, calendarName: String, location: String?,
        joinURL: URL? = nil, tint: UInt32? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.location = location
        self.joinURL = joinURL
        self.tint = tint
    }
}

/// Finds the video call link of a meeting in its location, notes or URL.
public enum MeetingLink {
    /// Hosts of the common video call services; subdomains count too.
    static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com",
    ]

    /// The first https link to a video call service in the texts, in order.
    public static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url, url.scheme == "https", let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}

/// What is on today and tomorrow, seen from a moment in time.
public struct Agenda: Equatable, Sendable {
    /// Today's events that are not over yet: all-day ones first, then by start time.
    public let today: [AgendaEvent]
    public let tomorrow: [AgendaEvent]
    /// Timed events running right now.
    public let current: [AgendaEvent]
    /// The next timed event that has not started.
    public let next: AgendaEvent?

    public init(events: [AgendaEvent], now: Date, calendar: Calendar) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now

        let ordered = events.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return ($0.start, $0.id) < ($1.start, $1.id)
        }
        today = ordered.filter { $0.start < startOfTomorrow && $0.end > now }
        tomorrow = ordered.filter { $0.start < endOfTomorrow && $0.end > startOfTomorrow }
        current = ordered.filter { !$0.isAllDay && $0.start <= now && $0.end > now }
        next = events
            .filter { !$0.isAllDay && $0.start > now }
            .min { ($0.start, $0.id) < ($1.start, $1.id) }
    }
}

/// Decides when to announce a meeting: once, a set number of minutes before it starts.
public struct MeetingAlertPlanner: Sendable {
    public var leadMinutes: Int
    /// Meetings already announced, by id and start time; a meeting that moves is announced again.
    private var announced: Set<String> = []

    public init(leadMinutes: Int) {
        self.leadMinutes = leadMinutes
    }

    /// The meetings to announce now: timed, not yet started, starting within the lead time,
    /// and not announced before.
    public mutating func due(events: [AgendaEvent], now: Date) -> [AgendaEvent] {
        let lead = TimeInterval(leadMinutes * 60)
        let due = events.filter { event in
            guard !event.isAllDay, event.start > now, event.start.timeIntervalSince(now) <= lead else { return false }
            return !announced.contains(Self.key(event))
        }
        due.forEach { announced.insert(Self.key($0)) }
        return due.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Whole minutes until the event starts, rounded up; never below 1.
    public static func minutesUntil(_ event: AgendaEvent, from now: Date) -> Int {
        max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
    }

    private static func key(_ event: AgendaEvent) -> String {
        "\(event.id)|\(event.start.timeIntervalSince1970)"
    }
}

/// A reminder as the notch shows it.
public struct AgendaReminder: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var due: Date?
    /// False when the reminder is due on a day, at no particular time; `due` is then that day's start.
    public var dueHasTime: Bool
    public var isCompleted: Bool
    public var listName: String
    /// When it was finished; nil for an open reminder.
    public var completedAt: Date?

    public init(
        id: String, title: String, due: Date?, dueHasTime: Bool = true, isCompleted: Bool, listName: String,
        completedAt: Date? = nil
    ) {
        self.completedAt = completedAt
        self.id = id
        self.title = title
        self.due = due
        self.dueHasTime = dueHasTime
        self.isCompleted = isCompleted
        self.listName = listName
    }

    /// A reminder due on a day, at no particular time, is overdue only once that day is over.
    public func isOverdue(at now: Date, calendar: Calendar) -> Bool {
        guard let due else { return false }
        if dueHasTime { return due < now }
        return due < calendar.startOfDay(for: now)
    }

    /// Open reminders worth showing now: those due by the end of tomorrow (overdue first),
    /// then those without a date. Later ones are left out.
    public static func upcoming(_ reminders: [AgendaReminder], now: Date, calendar: Calendar) -> [AgendaReminder] {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now
        let open = reminders.filter { !$0.isCompleted }
        let dated = open
            .filter { ($0.due ?? .distantFuture) < endOfTomorrow }
            .sorted { ($0.due ?? .distantFuture, $0.id) < ($1.due ?? .distantFuture, $1.id) }
        let undated = open.filter { $0.due == nil }.sorted { $0.id < $1.id }
        return dated + undated
    }
}

/// Reads and writes the calendar settings.
public struct CalendarSettingsStore {
    public enum Key {
        public static let meetingAlerts = "calendar.meetingAlerts"
        public static let leadMinutes = "calendar.leadMinutes"
        public static let showsLunarDate = "calendar.showsLunarDate"
        public static let estimates = "calendar.estimates"
    }

    public static let leadChoices = [1, 5, 10, 15]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Announce a meeting beside the notch shortly before it starts.
    public var meetingAlerts: Bool {
        get { defaults.object(forKey: Key.meetingAlerts) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.meetingAlerts) }
    }

    /// Whether the lunar date is shown until the user says: yes where the first language
    /// of the Mac is one whose speakers keep that calendar.
    public static func lunarByDefault(languages: [String]) -> Bool {
        guard let first = languages.first?.lowercased() else { return false }
        return first.hasPrefix("vi") || first.hasPrefix("zh")
    }

    /// How many minutes each reminder's work is thought to take, by the reminder's
    /// identifier. Kept here because the system's reminders have no place for it.
    public var estimates: [String: Int] {
        get { defaults.object(forKey: Key.estimates) as? [String: Int] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.estimates) }
    }

    /// Show today's lunar date beside the week on the calendar page.
    public var showsLunarDate: Bool {
        get {
            defaults.object(forKey: Key.showsLunarDate) as? Bool
                ?? Self.lunarByDefault(languages: Locale.preferredLanguages)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.showsLunarDate) }
    }

    public var leadMinutes: Int {
        get {
            guard let value = defaults.object(forKey: Key.leadMinutes) as? Int, Self.leadChoices.contains(value) else {
                return 5
            }
            return value
        }
        nonmutating set { defaults.set(newValue, forKey: Key.leadMinutes) }
    }
}
