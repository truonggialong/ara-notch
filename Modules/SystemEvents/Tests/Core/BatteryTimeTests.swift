import Testing
@testable import SystemEventsCore

@Suite struct BatteryTimeTests {
    @Test func theTimeLeftIsWrittenAsHoursAndMinutes() {
        #expect(BatteryTime.clock(minutes: 245) == "4:05")
        #expect(BatteryTime.clock(minutes: 59) == "0:59")
    }

    @Test func aTimeTheSystemHasNotWorkedOutYetIsNotShown() {
        #expect(BatteryTime.clock(minutes: nil) == nil)
        #expect(BatteryTime.clock(minutes: -1) == nil)
        #expect(BatteryTime.clock(minutes: 0) == nil)
    }

    @Test func aSnapshotKeepsTheTimeItWasGiven() {
        var snapshot = PowerSnapshot(isOnAC: false, isCharging: false, percent: 82)
        #expect(snapshot.minutesLeft == nil)
        snapshot.minutesLeft = 245
        #expect(snapshot.minutesLeft == 245)
    }
}
