import Foundation
import Testing
@testable import TimerCore

@Suite struct TimerPresetsTests {
    @Test func startWithTheFourTheAppAlwaysHad() {
        #expect(TimerSettingsStore(defaults: InMemoryDefaults()).presets == [5, 15, 25, 45])
    }

    @Test func aNewPresetIsKeptInOrderAndRemembered() {
        let defaults = InMemoryDefaults()
        let store = TimerSettingsStore(defaults: defaults)
        #expect(store.addPreset(10))
        #expect(TimerSettingsStore(defaults: defaults).presets == [5, 10, 15, 25, 45])
    }

    @Test func aPresetThatIsAlreadyThereIsNotAddedTwice() {
        let store = TimerSettingsStore(defaults: InMemoryDefaults())
        #expect(!store.addPreset(25))
        #expect(store.presets == [5, 15, 25, 45])
    }

    @Test func thereIsRoomForSixPresets() {
        let store = TimerSettingsStore(defaults: InMemoryDefaults())
        #expect(store.addPreset(10))
        #expect(store.addPreset(60))
        #expect(!store.addPreset(90))
        #expect(store.presets.count == 6)
        #expect(!store.canAddPreset(90))
    }

    @Test func aPresetOutsideTheTimersRangeIsRefused() {
        let store = TimerSettingsStore(defaults: InMemoryDefaults())
        #expect(!store.addPreset(0))
        #expect(!store.addPreset(181))
    }

    @Test func aPresetCanBeRemovedButNotTheLastOne() {
        let store = TimerSettingsStore(defaults: InMemoryDefaults())
        for minutes in [5, 15, 25] {
            #expect(store.removePreset(minutes))
        }
        #expect(store.presets == [45])
        #expect(!store.removePreset(45))
        #expect(store.presets == [45])
    }

    @Test func damagedStoredPresetsFallBackToTheUsualFour() {
        let defaults = InMemoryDefaults()
        defaults.set(["a", "b"], forKey: TimerSettingsStore.Key.presets)
        #expect(TimerSettingsStore(defaults: defaults).presets == [5, 15, 25, 45])
        defaults.set([Int](), forKey: TimerSettingsStore.Key.presets)
        #expect(TimerSettingsStore(defaults: defaults).presets == [5, 15, 25, 45])
    }

    @Test func theLabelIsTrimmedAndKeptShort() {
        let store = TimerSettingsStore(defaults: InMemoryDefaults())
        #expect(store.label == "")
        store.label = "  Pha trà  "
        #expect(store.label == "Pha trà")
        store.label = String(repeating: "a", count: 80)
        #expect(store.label.count == TimerSettingsStore.maxLabelLength)
    }
}
