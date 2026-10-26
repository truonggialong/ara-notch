import Foundation
import Testing
@testable import CalendarCore

private let utc = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}

/// A time on 12 October 2026 (or `day` days later), local time.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + day, hour: hour, minute: minute))!
}

private func event(_ id: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
    AgendaEvent(id: id, title: title, start: start, end: end, isAllDay: allDay, calendarName: "Việc", location: nil)
}

@Suite struct AgendaTests {
    private let events = [
        event("late", "Họp tối", at(20), at(21)),
        event("past", "Họp sáng", at(8), at(9)),
        event("now", "Đang họp", at(9, 30), at(10, 30)),
        event("allday", "Nghỉ lễ", at(0), at(0, day: 1), allDay: true),
        event("tomorrow", "Gặp khách", at(14, day: 1), at(15, day: 1)),
        event("far", "Tuần sau", at(9, day: 7), at(10, day: 7)),
    ]

    @Test func groupsTodayAndTomorrowAndDropsWhatIsOver() {
        let agenda = Agenda(events: events, now: at(10), calendar: calendar)
        #expect(agenda.today.map(\.id) == ["allday", "now", "late"])
        #expect(agenda.tomorrow.map(\.id) == ["tomorrow"])
    }

    @Test func anEventEndingExactlyNowIsOver() {
        let agenda = Agenda(events: events, now: at(10, 30), calendar: calendar)
        #expect(agenda.today.map(\.id) == ["allday", "late"])
    }

    @Test func theNextTimedEventSkipsAllDayAndRunningOnes() {
        #expect(Agenda(events: events, now: at(10), calendar: calendar).next?.id == "late")
        #expect(Agenda(events: events, now: at(21, 30), calendar: calendar).next?.id == "tomorrow")
        #expect(Agenda(events: [], now: at(10), calendar: calendar).next == nil)
    }

    @Test func knowsWhatIsHappeningNow() {
        let agenda = Agenda(events: events, now: at(10), calendar: calendar)
        #expect(agenda.current.map(\.id) == ["now"])
    }

    @Test func aMultiDayEventShowsOnBothDays() {
        let trip = event("trip", "Công tác", at(18), at(11, day: 1))
        let agenda = Agenda(events: [trip], now: at(10), calendar: calendar)
        #expect(agenda.today.map(\.id) == ["trip"])
        #expect(agenda.tomorrow.map(\.id) == ["trip"])
    }
}

@Suite struct MeetingAlertTests {
    private let meeting = event("m1", "Họp nhóm", at(10), at(11))

    @Test func alertsOnceWhenTheLeadTimeIsReached() {
        var planner = MeetingAlertPlanner(leadMinutes: 5)
        #expect(planner.due(events: [meeting], now: at(9, 54)).isEmpty)
        #expect(planner.due(events: [meeting], now: at(9, 55)).map(\.id) == ["m1"])
        #expect(planner.due(events: [meeting], now: at(9, 56)).isEmpty)
    }

    @Test func aMeetingAlreadyStartedIsNotAnnounced() {
        var planner = MeetingAlertPlanner(leadMinutes: 5)
        #expect(planner.due(events: [meeting], now: at(10, 1)).isEmpty)
    }

    @Test func allDayEventsAreNeverAnnounced() {
        var planner = MeetingAlertPlanner(leadMinutes: 5)
        let holiday = event("h", "Nghỉ lễ", at(0), at(0, day: 1), allDay: true)
        #expect(planner.due(events: [holiday], now: at(23, 57, day: -1)).isEmpty)
    }

    @Test func aMovedMeetingIsAnnouncedAgainForItsNewTime() {
        var planner = MeetingAlertPlanner(leadMinutes: 5)
        #expect(planner.due(events: [meeting], now: at(9, 56)).count == 1)
        let moved = event("m1", "Họp nhóm", at(15), at(16))
        #expect(planner.due(events: [moved], now: at(14, 56)).count == 1)
    }

    @Test func minutesUntilRoundsUp() {
        #expect(MeetingAlertPlanner.minutesUntil(meeting, from: at(9, 55)) == 5)
        #expect(MeetingAlertPlanner.minutesUntil(meeting, from: at(9, 55).addingTimeInterval(20)) == 5)
        #expect(MeetingAlertPlanner.minutesUntil(meeting, from: at(9, 59).addingTimeInterval(30)) == 1)
    }
}

@Suite struct ReminderListTests {
    private func reminder(_ id: String, due: Date?, done: Bool = false) -> AgendaReminder {
        AgendaReminder(id: id, title: id, due: due, isCompleted: done, listName: "Nhắc")
    }

    @Test func showsOverdueAndTodayFirstThenUndated() {
        let reminders = [
            reminder("undated", due: nil),
            reminder("today", due: at(17)),
            reminder("overdue", due: at(9, day: -2)),
            reminder("nextweek", due: at(9, day: 6)),
            reminder("done", due: at(9), done: true),
            reminder("tomorrow", due: at(9, day: 1)),
        ]
        let list = AgendaReminder.upcoming(reminders, now: at(10), calendar: calendar)
        #expect(list.map(\.id) == ["overdue", "today", "tomorrow", "undated"])
    }

    @Test func tellsOverdueFromDue() {
        #expect(reminder("a", due: at(9)).isOverdue(at: at(10), calendar: calendar))
        #expect(!reminder("a", due: at(11)).isOverdue(at: at(10), calendar: calendar))
        #expect(!reminder("a", due: nil).isOverdue(at: at(10), calendar: calendar))
    }

    @Test func aReminderDueOnADayIsOverdueOnlyOnceTheDayIsOver() {
        var wholeDay = reminder("a", due: at(0))
        wholeDay.dueHasTime = false
        #expect(!wholeDay.isOverdue(at: at(23, 59), calendar: calendar))
        #expect(wholeDay.isOverdue(at: at(0, 1, day: 1), calendar: calendar))
    }
}

@Suite struct CalendarSettingsStoreTests {
    @Test func meetingAlertsAreOnFiveMinutesAhead() {
        let store = CalendarSettingsStore(defaults: InMemoryDefaults())
        #expect(store.meetingAlerts == true)
        #expect(store.leadMinutes == 5)
    }

    @Test func leadTimeIsOneOfTheChoices() {
        let defaults = InMemoryDefaults()
        let store = CalendarSettingsStore(defaults: defaults)
        store.leadMinutes = 10
        store.meetingAlerts = false
        #expect(CalendarSettingsStore(defaults: defaults).leadMinutes == 10)
        #expect(CalendarSettingsStore(defaults: defaults).meetingAlerts == false)
        defaults.set(7, forKey: CalendarSettingsStore.Key.leadMinutes)
        #expect(store.leadMinutes == 5)
    }
}

@Suite struct MeetingLinkTests {
    @Test func findsAVideoCallLinkInAnyOfTheTexts() {
        #expect(MeetingLink.find(in: ["Phòng 3", "Vào https://meet.google.com/abc-defg-hij nhé"])?.absoluteString
            == "https://meet.google.com/abc-defg-hij")
        #expect(MeetingLink.find(in: [nil, "https://us02web.zoom.us/j/123456?pwd=x."])?.absoluteString
            == "https://us02web.zoom.us/j/123456?pwd=x")
        #expect(MeetingLink.find(in: ["<https://teams.microsoft.com/l/meetup-join/19%3a>"])?.host
            == "teams.microsoft.com")
    }

    @Test func otherLinksAreNotMeetings() {
        #expect(MeetingLink.find(in: ["https://example.com/agenda", "https://notzoom.us/j/1"]) == nil)
        #expect(MeetingLink.find(in: ["http://zoom.us/j/1"]) == nil)
        #expect(MeetingLink.find(in: [nil, ""]) == nil)
    }

    @Test func theFirstMeetingLinkWins() {
        let text = "Tài liệu https://example.com/a, họp https://zoom.us/j/1 hoặc https://meet.google.com/x"
        #expect(MeetingLink.find(in: [text])?.absoluteString == "https://zoom.us/j/1")
    }
}
