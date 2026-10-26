import Foundation
import Testing
@testable import SystemEventsCore

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct CapsLockDetectorTests {
    @Test func firstReadingIsSilent() {
        var detector = CapsLockDetector()
        #expect(detector.update(isOn: true) == nil)
    }

    @Test func changesAreReported() {
        var detector = CapsLockDetector()
        _ = detector.update(isOn: false)
        #expect(detector.update(isOn: true) == .on)
        #expect(detector.update(isOn: true) == nil)
        #expect(detector.update(isOn: false) == .off)
    }
}

@Suite struct ConnectivityDebouncerTests {
    @Test func startOnlineIsSilent() {
        var debouncer = ConnectivityDebouncer()
        #expect(debouncer.update(isOnline: true, at: at(0)) == nil)
        #expect(debouncer.nextDeadline == nil)
        #expect(debouncer.advance(to: at(100)) == nil)
    }

    @Test func offlineIsReportedAfter3Seconds() {
        var debouncer = ConnectivityDebouncer()
        _ = debouncer.update(isOnline: true, at: at(0))
        #expect(debouncer.update(isOnline: false, at: at(10)) == nil)
        #expect(debouncer.nextDeadline == at(13))
        #expect(debouncer.advance(to: at(12.9)) == nil)
        #expect(debouncer.advance(to: at(13)) == .offline)
        #expect(debouncer.nextDeadline == nil)
        #expect(debouncer.advance(to: at(20)) == nil)
    }

    @Test func flappingIsNotReported() {
        var debouncer = ConnectivityDebouncer()
        _ = debouncer.update(isOnline: true, at: at(0))
        for start in [10.0, 20.0, 30.0] {
            #expect(debouncer.update(isOnline: false, at: at(start)) == nil)
            #expect(debouncer.update(isOnline: true, at: at(start + 2)) == nil)
            #expect(debouncer.advance(to: at(start + 5)) == nil)
        }
    }

    @Test func onlineAfterReportedOfflineIsImmediate() {
        var debouncer = ConnectivityDebouncer()
        _ = debouncer.update(isOnline: true, at: at(0))
        _ = debouncer.update(isOnline: false, at: at(10))
        #expect(debouncer.advance(to: at(13)) == .offline)
        #expect(debouncer.update(isOnline: true, at: at(40)) == .online)
        #expect(debouncer.update(isOnline: true, at: at(41)) == nil)
    }

    @Test func startingOfflineIsReportedAfterDelay() {
        var debouncer = ConnectivityDebouncer()
        #expect(debouncer.update(isOnline: false, at: at(0)) == nil)
        #expect(debouncer.advance(to: at(3)) == .offline)
    }

    @Test func repeatedOfflineUpdatesDoNotExtendTheDelay() {
        var debouncer = ConnectivityDebouncer()
        _ = debouncer.update(isOnline: true, at: at(0))
        _ = debouncer.update(isOnline: false, at: at(10))
        #expect(debouncer.update(isOnline: false, at: at(12)) == nil)
        #expect(debouncer.nextDeadline == at(13))
    }

    @Test func lateOfflineUpdateReportsWithoutAdvance() {
        var debouncer = ConnectivityDebouncer()
        _ = debouncer.update(isOnline: true, at: at(0))
        _ = debouncer.update(isOnline: false, at: at(10))
        #expect(debouncer.update(isOnline: false, at: at(20)) == .offline)
    }
}

@Suite struct AlertSettingsStoreTests {
    @Test func everythingIsOnByDefault() {
        let store = AlertSettingsStore(defaults: InMemoryDefaults())
        #expect(store.power && store.capsLock && store.network)
    }

    @Test func valuesRoundTrip() {
        let defaults = InMemoryDefaults()
        let store = AlertSettingsStore(defaults: defaults)
        store.power = false
        store.capsLock = false
        store.network = false
        let reopened = AlertSettingsStore(defaults: defaults)
        #expect(!reopened.power && !reopened.capsLock && !reopened.network)
    }

    @Test func wrongTypesFallBackToOn() {
        let defaults = InMemoryDefaults()
        for key in [AlertSettingsStore.Key.power, AlertSettingsStore.Key.capsLock, AlertSettingsStore.Key.network] {
            defaults.set("abc", forKey: key)
        }
        let store = AlertSettingsStore(defaults: defaults)
        #expect(store.power && store.capsLock && store.network)
    }
}
