import Testing
@testable import SystemEventsCore

private func battery(_ percent: Int) -> PowerSnapshot {
    PowerSnapshot(isOnAC: false, isCharging: false, percent: percent)
}

private func plugged(_ percent: Int) -> PowerSnapshot {
    PowerSnapshot(isOnAC: true, isCharging: percent < 100, percent: percent)
}

/// Feeds the snapshots in order and returns the events of each one.
private func events(_ snapshots: [PowerSnapshot]) -> [[PowerEvent]] {
    var detector = PowerEventDetector()
    return snapshots.map { detector.update($0) }
}

@Suite struct PowerEventDetectorTests {
    @Test func firstSnapshotIsSilent() {
        #expect(events([battery(80)]) == [[]])
        #expect(events([plugged(80)]) == [[]])
    }

    @Test func plugAndUnplug() {
        #expect(events([battery(50), plugged(50), plugged(51), battery(51)])
            == [[], [.pluggedIn(percent: 50)], [], [.unplugged(percent: 51)]])
    }

    @Test func lowAt20ThenAt10() {
        #expect(events([battery(25), battery(20), battery(15), battery(10), battery(9)])
            == [[], [.low(percent: 20)], [], [.low(percent: 10)], []])
    }

    @Test func oscillationAroundThresholdAlertsOnce() {
        #expect(events([battery(21), battery(20), battery(21), battery(20)])
            == [[], [.low(percent: 20)], [], []])
    }

    @Test func skippingPastBothThresholdsAlertsOnceWithLowest() {
        #expect(events([battery(30), battery(5)]) == [[], [.low(percent: 5)]])
    }

    @Test func pluggingInResetsLowAlerts() {
        #expect(events([battery(30), battery(20), plugged(20), battery(21), battery(20)])
            == [[], [.low(percent: 20)], [.pluggedIn(percent: 20)], [.unplugged(percent: 21)], [.low(percent: 20)]])
    }

    @Test func unpluggingBelowThresholdAlertsLow() {
        #expect(events([plugged(15), battery(15)]) == [[], [.unplugged(percent: 15), .low(percent: 15)]])
    }

    @Test func noLowAlertWhileOnAC() {
        #expect(events([plugged(25), plugged(19), plugged(9)]) == [[], [], []])
    }

    @Test func fullOncePerPlugIn() {
        #expect(events([plugged(99), plugged(100), plugged(100)]) == [[], [.full], []])
        #expect(events([plugged(100), battery(100), plugged(100)])
            == [[], [.unplugged(percent: 100)], [.pluggedIn(percent: 100), .full]])
    }

    @Test func startingLowOnBatteryAlertsOnce() {
        #expect(events([battery(8), battery(7)]) == [[.low(percent: 8)], []])
    }

    @Test func startingFullOnACIsSilent() {
        #expect(events([plugged(100), plugged(100)]) == [[], []])
    }

    @Test func noBatteryIsSilent() {
        let desktop = PowerSnapshot(hasBattery: false, isOnAC: true, isCharging: false, percent: 0)
        #expect(events([desktop, desktop]) == [[], []])
    }
}
