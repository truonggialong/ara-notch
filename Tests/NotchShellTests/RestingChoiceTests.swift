import Testing
@testable import NotchShell

@Suite struct RestingChoiceTests {
    @Test func theMoreImportantRestingThingShows() {
        #expect(NotchController.restingChoice(["media.playing": 0, "capslock": 1]) == "capslock")
    }

    @Test func whenItGoesTheOtherComesBack() {
        #expect(NotchController.restingChoice(["media.playing": 0]) == "media.playing")
        #expect(NotchController.restingChoice([:]) == nil)
    }
}
