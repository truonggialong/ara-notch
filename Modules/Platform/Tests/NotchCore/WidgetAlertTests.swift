import Foundation
import Testing
@testable import NotchCore

@Suite struct WidgetAlertTests {
    @Test func aLowBatteryAlertsOnlyWhileNotCharging() {
        #expect(WidgetAlert.battery(percent: 20, isCharging: false))
        #expect(!WidgetAlert.battery(percent: 21, isCharging: false))
        #expect(!WidgetAlert.battery(percent: 5, isCharging: true))
        #expect(!WidgetAlert.battery(percent: nil, isCharging: false))
    }

    @Test func usageAlertsFromNinetyPercent() {
        #expect(!WidgetAlert.usage(percent: 89))
        #expect(WidgetAlert.usage(percent: 90))
        #expect(!WidgetAlert.usage(percent: nil))
    }

    @Test func aTimerAlertsInItsLastMinuteAndWhenDone() {
        #expect(WidgetAlert.timer(remaining: 59, isFinished: false))
        #expect(!WidgetAlert.timer(remaining: 60, isFinished: false))
        #expect(WidgetAlert.timer(remaining: 0, isFinished: true))
    }

    @Test func agentsAlertWhenOneWaits() {
        #expect(!WidgetAlert.agents(waiting: 0))
        #expect(WidgetAlert.agents(waiting: 1))
    }
}

@Suite struct WidgetMeasureTests {
    @Test func aBarIsNeverFilledBackwardsOrPastItsEnd() {
        #expect(WidgetMeasure.fraction(-0.2) == 0)
        #expect(WidgetMeasure.fraction(0.4) == 0.4)
        #expect(WidgetMeasure.fraction(1.7) == 1)
        #expect(WidgetMeasure.fraction(.nan) == 0)
    }

    @Test func fiveSegmentsShowAnyChargeAtAll() {
        #expect([0, 5, 20, 30, 83, 100, 120, -4].map { WidgetMeasure.segments(percent: $0, of: 5) } == [0, 1, 1, 2, 4, 5, 5, 0])
    }
}

@Suite struct WidgetSpanTests {
    @Test func aSpanKeepsItsPlaceAndLength() {
        let span = WidgetMeasure.span(0.2...0.3, minimumShare: 0.01)
        #expect(abs(span.start - 0.2) < 1e-9 && abs(span.length - 0.1) < 1e-9)
    }

    @Test func aShortSpanAtTheEndIsWidenedInwardsNotPastTheBar() {
        let span = WidgetMeasure.span(0.998...1.0, minimumShare: 0.01)
        #expect(abs(span.start - 0.99) < 1e-9 && abs(span.length - 0.01) < 1e-9)
    }

    @Test func aSpanPastTheBarIsKeptOnIt() {
        let span = WidgetMeasure.span(1.2...1.5, minimumShare: 0.01)
        #expect(abs(span.start - 0.99) < 1e-9 && abs(span.length - 0.01) < 1e-9)
        let early = WidgetMeasure.span(-0.5...0.1, minimumShare: 0.01)
        #expect(abs(early.start) < 1e-9 && abs(early.length - 0.1) < 1e-9)
    }
}
