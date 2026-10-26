import Testing
@testable import SystemEventsCore

@Suite struct MediaKeyTests {
    /// Builds the `data1` field of a system-defined key event: key code, state and repeat flag.
    private func data1(key: Int, down: Bool, isRepeat: Bool = false) -> Int {
        (key << 16) | ((down ? 0xA : 0xB) << 8) | (isRepeat ? 1 : 0)
    }

    @Test func readsTheFiveKeysTheHUDShows() {
        #expect(MediaKeyEvent(data1: data1(key: 0, down: true))?.key == .volumeUp)
        #expect(MediaKeyEvent(data1: data1(key: 1, down: true))?.key == .volumeDown)
        #expect(MediaKeyEvent(data1: data1(key: 7, down: true))?.key == .mute)
        #expect(MediaKeyEvent(data1: data1(key: 2, down: true))?.key == .brightnessUp)
        #expect(MediaKeyEvent(data1: data1(key: 3, down: true))?.key == .brightnessDown)
    }

    @Test func tellsPressFromReleaseAndRepeat() {
        #expect(MediaKeyEvent(data1: data1(key: 0, down: true))?.isDown == true)
        #expect(MediaKeyEvent(data1: data1(key: 0, down: false))?.isDown == false)
        #expect(MediaKeyEvent(data1: data1(key: 0, down: true, isRepeat: true))?.isRepeat == true)
        #expect(MediaKeyEvent(data1: data1(key: 0, down: true))?.isRepeat == false)
    }

    @Test(arguments: [16, 17, 19, 20, 23, 99])
    func leavesOtherKeysAlone(_ key: Int) {
        // Play, next, previous, keyboard backlight and anything else pass through untouched.
        #expect(MediaKeyEvent(data1: data1(key: key, down: true)) == nil)
    }

    @Test func stepsInSixteenthsAndStopsAtTheEnds() {
        #expect(LevelStepper.step(0.5, up: true) == 0.5625)
        #expect(LevelStepper.step(0.5, up: false) == 0.4375)
        #expect(LevelStepper.step(0.98, up: true) == 1)
        #expect(LevelStepper.step(0.03, up: false) == 0)
        #expect(LevelStepper.step(1, up: true) == 1)
        #expect(LevelStepper.step(0, up: false) == 0)
    }

    @Test func aLevelBetweenStepsSnapsToTheNextStep() {
        // 0.53 is between 8/16 and 9/16.
        #expect(LevelStepper.step(0.53, up: true) == 0.5625)
        #expect(LevelStepper.step(0.53, up: false) == 0.5)
    }

    @Test func fineStepsAreAQuarterOfANormalOne() {
        #expect(LevelStepper.step(0.5, up: true, fine: true) == 0.515625)
        #expect(LevelStepper.step(0.5, up: false, fine: true) == 0.484375)
    }

    @Test func theHUDIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = AlertSettingsStore(defaults: defaults)
        #expect(store.replacesHUD == false)
        store.replacesHUD = true
        #expect(AlertSettingsStore(defaults: defaults).replacesHUD == true)
        // The other alerts still default to on.
        #expect(store.power == true)
    }
}

@Suite struct KeyboardLightKeyTests {
    @Test func readsTheKeyboardLightKeys() {
        #expect(MediaKeyEvent(data1: (21 << 16) | (0xA << 8))?.key == .keyboardLightUp)
        #expect(MediaKeyEvent(data1: (22 << 16) | (0xA << 8))?.key == .keyboardLightDown)
        #expect(MediaKeyEvent(data1: (22 << 16) | (0xB << 8))?.isDown == false)
    }

    @Test func theKeyboardLightToggleKeyIsLeftToTheSystem() {
        #expect(MediaKeyEvent(data1: (23 << 16) | (0xA << 8)) == nil)
    }
}
