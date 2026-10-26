import Foundation
import Testing
@testable import ClipboardCore

@Suite struct ClipboardSettingsStoreTests {
    private typealias Key = ClipboardSettingsStore.Key

    @Test func defaultsWhenEmpty() {
        let store = ClipboardSettingsStore(defaults: InMemoryDefaults())
        #expect(store.isPaused == false)
        #expect(store.maxItems == 500)
        #expect(store.pasteOnClick == true)
        #expect(store.ignoredBundleIDs == [])
    }

    @Test func valuesRoundTrip() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        store.isPaused = true
        store.maxItems = 200
        store.pasteOnClick = false
        store.ignoredBundleIDs = ["com.apple.Safari", "com.1password.1password"]

        let reopened = ClipboardSettingsStore(defaults: defaults)
        #expect(reopened.isPaused == true)
        #expect(reopened.maxItems == 200)
        #expect(reopened.pasteOnClick == false)
        #expect(reopened.ignoredBundleIDs == ["com.apple.Safari", "com.1password.1password"])
    }

    @Test func maxItemsIsClampedOnWriteAndRead() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        store.maxItems = 5
        #expect(store.maxItems == 50)
        store.maxItems = 5000
        #expect(store.maxItems == 1000)
        defaults.set(7, forKey: Key.maxItems)
        #expect(store.maxItems == 50)
    }

    @Test func wrongTypesFallBackToDefaults() {
        let defaults = InMemoryDefaults()
        for key in [Key.isPaused, Key.maxItems, Key.pasteOnClick, Key.ignoredBundleIDs] {
            defaults.set("abc", forKey: key)
        }
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.isPaused == false)
        #expect(store.maxItems == 500)
        #expect(store.pasteOnClick == true)
        #expect(store.ignoredBundleIDs == [])
    }

    @Test func hotKeyIsEnabledByDefaultAndRoundTrips() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.hotKeyEnabled == true)
        store.hotKeyEnabled = false
        #expect(ClipboardSettingsStore(defaults: defaults).hotKeyEnabled == false)
        defaults.set("abc", forKey: Key.hotKeyEnabled)
        #expect(store.hotKeyEnabled == true)
    }

    @Test func linkPreviewsAreOnByDefaultAndRoundTrip() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.linkPreviews == true)
        store.linkPreviews = false
        #expect(ClipboardSettingsStore(defaults: defaults).linkPreviews == false)
        defaults.set("abc", forKey: Key.linkPreviews)
        #expect(store.linkPreviews == true)
    }

    @Test func retentionDefaultsToNeverAndRoundTrips() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.retention == .never)
        store.retention = .week
        #expect(ClipboardSettingsStore(defaults: defaults).retention == .week)
        defaults.set("bogus", forKey: Key.retention)
        #expect(store.retention == .never)
        defaults.set(7, forKey: Key.retention)
        #expect(store.retention == .never)
    }

    @Test func copyFeedbackIsOnByDefaultAndRoundTrips() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.copyFeedback == true)
        store.copyFeedback = false
        #expect(ClipboardSettingsStore(defaults: defaults).copyFeedback == false)
        defaults.set("abc", forKey: Key.copyFeedback)
        #expect(store.copyFeedback == true)
    }

    @Test func theCopiedSignHasItsOwnSwitchAndStartsAsTheSoundWas() {
        // Until 0.23.0 one setting gave both the sound and the sign.
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.copySign == true)
        store.copyFeedback = false
        #expect(store.copySign == false)
        store.copySign = true
        #expect(ClipboardSettingsStore(defaults: defaults).copySign == true)
        #expect(ClipboardSettingsStore(defaults: defaults).copyFeedback == false)
    }

    @Test func ignoredBundleIDsAreCleaned() {
        let store = ClipboardSettingsStore(defaults: InMemoryDefaults())
        store.ignoredBundleIDs = ["a", "", "a", " b "]
        #expect(store.ignoredBundleIDs == ["a", "b"])
    }

    @Test func bareHexColoursAreOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.bareHexColors == false)
        store.bareHexColors = true
        #expect(ClipboardSettingsStore(defaults: defaults).bareHexColors == true)
    }

    @Test func agentAccessIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.mcpEnabled == false)
        #expect(ClipboardSettingsStore.Key.mcpEnabled == "clipboard.mcpEnabled")
        store.mcpEnabled = true
        #expect(ClipboardSettingsStore(defaults: defaults).mcpEnabled == true)
    }
}
