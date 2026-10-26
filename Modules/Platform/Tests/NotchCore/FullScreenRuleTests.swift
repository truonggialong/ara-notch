import CoreGraphics
import Testing
@testable import NotchCore

/// Window bounds are measured from the top left of the main display, as the window list gives them.
@Suite struct FullScreenRuleTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: -572, width: 2560, height: 1440)

    private func window(_ bounds: CGRect, layer: Int = 0, mine: Bool = false) -> FullScreenRule.Window {
        FullScreenRule.Window(bounds: bounds, layer: layer, isOwn: mine)
    }

    @Test func aWindowAsLargeAsADisplayMakesItFullScreen() {
        let covered = FullScreenRule.coveredDisplays(windows: [window(external)], displays: [builtIn, external])
        #expect(covered == [1])
    }

    @Test func aMaximisedWindowUnderTheMenuBarIsNotFullScreen() {
        let maximised = CGRect(x: 1512, y: -572 + 25, width: 2560, height: 1440 - 25)
        #expect(FullScreenRule.coveredDisplays(windows: [window(maximised)], displays: [builtIn, external]).isEmpty)
    }

    @Test func theDockTheMenuBarAndTheNotchItselfDoNotCount() {
        let windows = [window(builtIn, layer: 20), window(builtIn, layer: 24), window(builtIn, mine: true)]
        #expect(FullScreenRule.coveredDisplays(windows: windows, displays: [builtIn, external]).isEmpty)
    }

    @Test func eachDisplayIsJudgedOnItsOwn() {
        let windows = [window(builtIn), window(CGRect(x: 1600, y: -500, width: 800, height: 600))]
        #expect(FullScreenRule.coveredDisplays(windows: windows, displays: [builtIn, external]) == [0])
    }

    @Test func boundsThatAreOffByAFractionStillCount() {
        let almost = CGRect(x: 1512.2, y: -572.4, width: 2559.6, height: 1440.3)
        #expect(FullScreenRule.coveredDisplays(windows: [window(almost)], displays: [builtIn, external]) == [1])
    }

    @Test func theNotchHidesOnlyWhenNothingTemporaryShows() {
        #expect(FullScreenRule.hidesNotch(isCovered: true, isEnabled: true, isOpen: false, showsNotice: false))
        // A notice still drops out of the notch over a full-screen app.
        #expect(!FullScreenRule.hidesNotch(isCovered: true, isEnabled: true, isOpen: false, showsNotice: true))
        // Opened with the shortcut, it shows.
        #expect(!FullScreenRule.hidesNotch(isCovered: true, isEnabled: true, isOpen: true, showsNotice: false))
        #expect(!FullScreenRule.hidesNotch(isCovered: true, isEnabled: false, isOpen: false, showsNotice: false))
        #expect(!FullScreenRule.hidesNotch(isCovered: false, isEnabled: true, isOpen: false, showsNotice: false))
    }

    @Test func theNotchHidesOverFullScreenAppsUnlessTheUserSaysOtherwise() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        #expect(store.hidesInFullScreen)
        store.hidesInFullScreen = false
        #expect(!ShellSettingsStore(defaults: defaults).hidesInFullScreen)
    }
}
