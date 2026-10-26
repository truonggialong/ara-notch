import Foundation
import Testing
@testable import NotchCore

/// Runs the body against an empty in-memory defaults store.
private func withDefaults(_ body: (UserDefaults) -> Void) {
    body(InMemoryDefaults())
}

@Suite struct ShellSettingsStoreTests {
    @Test func defaultsWhenEmpty() {
        withDefaults { defaults in
            let store = ShellSettingsStore(defaults: defaults)
            #expect(store.openOnHover == true)
            #expect(store.hoverDelay == 0.10)
            #expect(store.hapticsEnabled == true)
        }
    }

    @Test func valuesRoundTripThroughANewStore() {
        withDefaults { defaults in
            let store = ShellSettingsStore(defaults: defaults)
            store.openOnHover = false
            store.hoverDelay = 0.3
            store.hapticsEnabled = false

            let reopened = ShellSettingsStore(defaults: defaults)
            #expect(reopened.openOnHover == false)
            #expect(reopened.hoverDelay == 0.3)
            #expect(reopened.hapticsEnabled == false)
        }
    }

    @Test func hoverDelayIsClampedOnWrite() {
        withDefaults { defaults in
            let store = ShellSettingsStore(defaults: defaults)
            store.hoverDelay = 2
            #expect(store.hoverDelay == 0.5)
            #expect(defaults.double(forKey: ShellSettingsStore.Key.hoverDelay) == 0.5)
            store.hoverDelay = -1
            #expect(store.hoverDelay == 0)
        }
    }

    @Test func hoverDelayIsClampedOnRead() {
        withDefaults { defaults in
            defaults.set(9.0, forKey: ShellSettingsStore.Key.hoverDelay)
            #expect(ShellSettingsStore(defaults: defaults).hoverDelay == 0.5)
        }
    }

    @Test func wrongTypesFallBackToDefaults() {
        withDefaults { defaults in
            defaults.set("abc", forKey: ShellSettingsStore.Key.openOnHover)
            defaults.set("abc", forKey: ShellSettingsStore.Key.hoverDelay)
            defaults.set("abc", forKey: ShellSettingsStore.Key.hapticsEnabled)
            let store = ShellSettingsStore(defaults: defaults)
            #expect(store.openOnHover == true)
            #expect(store.hoverDelay == 0.10)
            #expect(store.hapticsEnabled == true)
        }
    }

    @Test func nanHoverDelayFallsBackToDefault() {
        withDefaults { defaults in
            defaults.set(Double.nan, forKey: ShellSettingsStore.Key.hoverDelay)
            let store = ShellSettingsStore(defaults: defaults)
            #expect(store.hoverDelay == 0.10)

            store.hoverDelay = 0.3
            store.hoverDelay = .nan
            #expect(store.hoverDelay == 0.10)
        }
    }
}

@Suite struct ShellPageSettingsTests {
    @Test func pageLayoutAndOptionsDefaultToNothingSpecial() {
        let store = ShellSettingsStore(defaults: InMemoryDefaults())
        #expect(store.pageOrder.isEmpty)
        #expect(store.hiddenPages.isEmpty)
        #expect(store.startPage == nil)
        #expect(store.hidesFromCapture == false)
    }

    @Test func pageLayoutAndOptionsAreRemembered() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        store.pageOrder = ["timer", "clipboard"]
        store.hiddenPages = ["about"]
        store.startPage = "timer"
        store.hidesFromCapture = true

        let reopened = ShellSettingsStore(defaults: defaults)
        #expect(reopened.pageOrder == ["timer", "clipboard"])
        #expect(reopened.hiddenPages == ["about"])
        #expect(reopened.startPage == "timer")
        #expect(reopened.hidesFromCapture == true)

        reopened.startPage = nil
        #expect(ShellSettingsStore(defaults: defaults).startPage == nil)
    }

    @Test func wrongTypesFallBack() {
        let defaults = InMemoryDefaults()
        defaults.set("abc", forKey: ShellSettingsStore.Key.pageOrder)
        defaults.set(5, forKey: ShellSettingsStore.Key.startPage)
        let store = ShellSettingsStore(defaults: defaults)
        #expect(store.pageOrder.isEmpty)
        #expect(store.startPage == nil)
    }
}

@Suite struct ShellSwipeSettingsTests {
    @Test func swipeDefaultsAndRoundTrip() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        #expect(store.swipeToOpen == true)
        #expect(store.swipeSensitivity == .medium)
        #expect(store.interactionPadding == ShellSettingsStore.defaultInteractionPadding)

        store.swipeToOpen = false
        store.swipeSensitivity = .high
        store.interactionPadding = 12
        let reopened = ShellSettingsStore(defaults: defaults)
        #expect(reopened.swipeToOpen == false)
        #expect(reopened.swipeSensitivity == .high)
        #expect(reopened.interactionPadding == 12)
    }

    @Test func interactionPaddingIsClampedAndBadValuesFallBack() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        store.interactionPadding = 500
        #expect(store.interactionPadding == ShellSettingsStore.interactionPaddingRange.upperBound)
        store.interactionPadding = -3
        #expect(store.interactionPadding == 0)
        defaults.set("wide", forKey: ShellSettingsStore.Key.interactionPadding)
        defaults.set("extreme", forKey: ShellSettingsStore.Key.swipeSensitivity)
        #expect(store.interactionPadding == ShellSettingsStore.defaultInteractionPadding)
        #expect(store.swipeSensitivity == .medium)
    }
}

@Suite struct AppAppearanceTests {
    @Test func followsTheSystemUntilChosen() {
        #expect(ShellSettingsStore(defaults: InMemoryDefaults()).appearance == .system)
    }

    @Test func theChoiceIsRemembered() {
        let defaults = InMemoryDefaults()
        ShellSettingsStore(defaults: defaults).appearance = .light
        #expect(ShellSettingsStore(defaults: defaults).appearance == .light)
    }

    @Test func theOldPanelOnlyChoiceCarriesOver() {
        let defaults = InMemoryDefaults()
        defaults.set("dark", forKey: "clipboard.panelAppearance")
        #expect(ShellSettingsStore(defaults: defaults).appearance == .dark)
        // Once chosen for the whole app, the old value no longer counts.
        ShellSettingsStore(defaults: defaults).appearance = .system
        #expect(ShellSettingsStore(defaults: defaults).appearance == .system)
    }

    @Test func aWelcomeIsShownOnlyUntilItHasBeenSeen() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        #expect(!store.hasSeenWelcome)
        store.hasSeenWelcome = true
        #expect(ShellSettingsStore(defaults: defaults).hasSeenWelcome)
    }
}

@Suite struct SettingsSearchTests {
    private let index: [SettingsSearch.Section] = [
        .init(id: "general", title: "General", phrases: ["Open the notch on hover", "Haptic feedback", "Appearance"]),
        .init(id: "clipboard", title: "Clipboard", phrases: ["Items to keep", "Sound and notice when copying", "Volume"]),
        .init(id: "timer", title: "Hẹn giờ", phrases: ["Âm báo khi hết giờ"]),
    ]

    @Test func anEmptySearchKeepsEverySection() {
        #expect(SettingsSearch.results(for: "  ", in: index).map(\.id) == ["general", "clipboard", "timer"])
    }

    @Test func findsASectionByItsOwnName() {
        let results = SettingsSearch.results(for: "clip", in: index)
        #expect(results.map(\.id) == ["clipboard"])
        #expect(results[0].phrases.isEmpty)
    }

    @Test func findsASectionByWhatIsInItAndSaysWhat() {
        let results = SettingsSearch.results(for: "volume", in: index)
        #expect(results.map(\.id) == ["clipboard"])
        #expect(results[0].phrases == ["Volume"])
    }

    @Test func ignoresCaseAndAccents() {
        #expect(SettingsSearch.results(for: "HAPTIC", in: index).map(\.id) == ["general"])
        #expect(SettingsSearch.results(for: "het gio", in: index).map(\.id) == ["timer"])
        #expect(SettingsSearch.results(for: "hen gio", in: index).map(\.id) == ["timer"])
    }

    @Test func findsNothingForWordsThatAreNowhere() {
        #expect(SettingsSearch.results(for: "zzz", in: index).isEmpty)
    }
}
