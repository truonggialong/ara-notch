import Foundation
import Testing
@testable import SystemEventsCore

@Suite struct KeepAwakeRulesTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func conditions(battery: Int? = 80, power: Bool = true, displays: Int = 0, apps: Set<String> = [], downloading: Bool = false) -> KeepAwakeConditions {
        KeepAwakeConditions(batteryPercent: battery, isOnPower: power, externalDisplays: displays, runningApps: apps, downloading: downloading)
    }

    @Test func untilATimeOfDayIsTodayOrTomorrow() {
        // 1_000_000 s is 13:46:40 UTC.
        let later = KeepAwakeSession.until(minutesOfDay: 17 * 60 + 30, now: now, calendar: calendar)
        #expect(later.ends == now.addingTimeInterval(3 * 3600 + 43 * 60 + 20))
        let earlier = KeepAwakeSession.until(minutesOfDay: 9 * 60, now: now, calendar: calendar)
        #expect(earlier.ends! > now)
        #expect(earlier.ends!.timeIntervalSince(now) > 19 * 3600)
    }

    @Test func extendingAddsToTheEndAndTheLength() {
        let session = KeepAwakeSession(ends: now.addingTimeInterval(300), length: 1800)
        let longer = session.extended(byMinutes: 30, now: now)
        #expect(longer.ends == now.addingTimeInterval(300 + 1800))
        #expect(longer.length == 3600)
    }

    @Test func eachKindOfSessionEndsOnItsOwnCondition() {
        let settings = KeepAwakeRules.Settings()
        let timed = KeepAwakeSession(ends: now, length: 60)
        #expect(KeepAwakeRules.stop(timed, conditions: conditions(), settings: settings, now: now) == .timeUp)
        let app = KeepAwakeSession(ends: nil, until: .app(bundleID: "us.zoom.xos", name: "Zoom"))
        #expect(KeepAwakeRules.stop(app, conditions: conditions(apps: ["us.zoom.xos"]), settings: settings, now: now) == nil)
        #expect(KeepAwakeRules.stop(app, conditions: conditions(), settings: settings, now: now) == .appQuit)
        let downloads = KeepAwakeSession(ends: nil, until: .downloads)
        #expect(KeepAwakeRules.stop(downloads, conditions: conditions(downloading: true), settings: settings, now: now) == nil)
        #expect(KeepAwakeRules.stop(downloads, conditions: conditions(), settings: settings, now: now) == .downloadsDone)
    }

    @Test func aLowBatteryOrBeingUnpluggedStopsAnySession() {
        let endless = KeepAwakeSession(ends: nil)
        let low = conditions(battery: 18, power: false)
        #expect(KeepAwakeRules.stop(endless, conditions: low, settings: .init(), now: now) == .lowBattery(18))
        #expect(KeepAwakeRules.stop(endless, conditions: conditions(battery: 18, power: true), settings: .init(), now: now) == nil)
        #expect(KeepAwakeRules.stop(endless, conditions: low, settings: .init(stopsOnLowBattery: false), now: now) == nil)
        let unplugged = KeepAwakeRules.Settings(stopsWhenUnplugged: true)
        #expect(KeepAwakeRules.stop(endless, conditions: conditions(power: false), settings: unplugged, now: now) == .unplugged)
    }

    @Test func theReminderComesFiveMinutesBeforeALongEnoughSession() {
        let hour = KeepAwakeSession(ends: now.addingTimeInterval(3600), length: 3600)
        #expect(KeepAwakeRules.reminder(for: hour) == now.addingTimeInterval(3300))
        #expect(KeepAwakeRules.reminder(for: KeepAwakeSession(ends: now.addingTimeInterval(300), length: 300)) == nil)
        #expect(KeepAwakeRules.reminder(for: KeepAwakeSession(ends: nil)) == nil)
    }

    @Test func triggersWantTheMacAwakeOnlyWhileTheirConditionHolds() {
        let apps = KeepAwakeRules.Settings(triggerApps: ["com.apple.Keynote"])
        #expect(KeepAwakeRules.trigger(conditions: conditions(apps: ["com.apple.Keynote"]), settings: apps, now: now, calendar: calendar) == "app:com.apple.Keynote")
        #expect(KeepAwakeRules.trigger(conditions: conditions(), settings: apps, now: now, calendar: calendar) == nil)
        let docked = KeepAwakeRules.Settings(triggerDocked: true)
        #expect(KeepAwakeRules.trigger(conditions: conditions(displays: 1), settings: docked, now: now, calendar: calendar) == "docked")
        #expect(KeepAwakeRules.trigger(conditions: conditions(power: false, displays: 1), settings: docked, now: now, calendar: calendar) == nil)
        // 1970-01-12 is a Monday; 13:46 is within 9:00–18:00.
        let schedule = KeepAwakeRules.Settings(triggerSchedule: true)
        #expect(KeepAwakeRules.trigger(conditions: conditions(), settings: schedule, now: now, calendar: calendar) == "schedule")
        let weekend = KeepAwakeRules.Settings(triggerSchedule: true, scheduleDays: [1, 7])
        #expect(KeepAwakeRules.trigger(conditions: conditions(), settings: weekend, now: now, calendar: calendar) == nil)
        #expect(KeepAwakeRules.trigger(conditions: conditions(battery: 10, power: false, apps: ["com.apple.Keynote"]), settings: apps, now: now, calendar: calendar) == nil)
    }
}
