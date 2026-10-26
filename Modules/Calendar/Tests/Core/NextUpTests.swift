import Foundation
import Testing
@testable import CalendarCore

@Suite struct NextUpTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ title: String, from start: Double, to end: Double, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(
            id: title, title: title, start: now.addingTimeInterval(start * 60), end: now.addingTimeInterval(end * 60),
            isAllDay: allDay, calendarName: "Lịch", location: nil)
    }

    private func reminder(_ title: String) -> AgendaReminder {
        AgendaReminder(id: title, title: title, due: nil, isCompleted: false, listName: "Nhắc")
    }

    @Test func aMeetingUnderWayIsNow() {
        let next = NextUp.find(events: [event("Họp", from: -10, to: 20)], reminders: [], at: now)
        #expect(next == .event(title: "Họp", timing: .now))
    }

    @Test func aMeetingWithinTheHourCountsDownInMinutes() {
        let next = NextUp.find(events: [event("Họp", from: 11.5, to: 40)], reminders: [], at: now)
        #expect(next == .event(title: "Họp", timing: .inMinutes(12)))
    }

    @Test func aLaterMeetingGivesItsTime() {
        let meeting = event("Họp", from: 90, to: 120)
        #expect(NextUp.find(events: [meeting], reminders: [], at: now) == .event(title: "Họp", timing: .at(meeting.start)))
    }

    @Test func finishedMeetingsAreSkipped() {
        let next = NextUp.find(events: [event("Sáng", from: -90, to: -30), event("Chiều", from: 30, to: 60)], reminders: [], at: now)
        #expect(next == .event(title: "Chiều", timing: .inMinutes(30)))
    }

    @Test func aTimedMeetingComesBeforeAnAllDayOne() {
        let next = NextUp.find(events: [event("Nghỉ lễ", from: -600, to: 800, allDay: true), event("Họp", from: 90, to: 120)], reminders: [], at: now)
        if case .event(let title, _) = next { #expect(title == "Họp") } else { Issue.record("no event") }
    }

    @Test func anAllDayEventIsShownWhenNothingElseIsTimed() {
        let next = NextUp.find(events: [event("Nghỉ lễ", from: -600, to: 800, allDay: true)], reminders: [reminder("Mua sữa")], at: now)
        #expect(next == .event(title: "Nghỉ lễ", timing: .allDay))
    }

    @Test func withNoEventTheFirstReminderIsNext() {
        #expect(NextUp.find(events: [], reminders: [reminder("Mua sữa"), reminder("Gọi điện")], at: now) == .reminder(title: "Mua sữa"))
        #expect(NextUp.find(events: [], reminders: [], at: now) == nil)
    }
}
