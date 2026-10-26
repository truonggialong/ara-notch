import Testing
@testable import ClipboardCore

@Suite struct CopyStackTests {
    @Test func nothingIsCollectedUntilTheStackIsStarted() {
        var stack = CopyStack()
        stack.push(1)
        #expect(!stack.isActive)
        #expect(stack.count == 0)
        #expect(stack.next() == nil)
    }

    @Test func pastesInTheOrderCopiedByDefault() {
        var stack = CopyStack()
        stack.start()
        stack.push(10)
        stack.push(20)
        stack.push(30)
        #expect(stack.count == 3)
        #expect(stack.peek == 10)
        #expect(stack.next() == 10)
        #expect(stack.next() == 20)
        #expect(stack.isActive)
        #expect(stack.next() == 30)
    }

    @Test func canPasteTheLastCopiedFirst() {
        var stack = CopyStack(order: .lastCopiedFirst)
        stack.start()
        stack.push(10)
        stack.push(20)
        stack.push(30)
        #expect(stack.peek == 30)
        #expect(stack.next() == 30)
        #expect(stack.next() == 20)
        #expect(stack.next() == 10)
    }

    @Test func theStackEndsItselfWithItsLastClip() {
        var stack = CopyStack()
        stack.start()
        stack.push(1)
        #expect(stack.next() == 1)
        #expect(!stack.isActive)
        // The next paste is an ordinary one again.
        #expect(stack.next() == nil)
    }

    @Test func anEmptyActiveStackLetsPastesThroughAndStaysActive() {
        var stack = CopyStack()
        stack.start()
        #expect(stack.next() == nil)
        #expect(stack.isActive)
        stack.push(5)
        #expect(stack.next() == 5)
    }

    @Test func theSameClipCanBeStackedTwice() {
        var stack = CopyStack()
        stack.start()
        stack.push(7)
        stack.push(7)
        #expect(stack.count == 2)
    }

    @Test func stoppingAndRestartingClearsTheStack() {
        var stack = CopyStack()
        stack.start()
        stack.push(1)
        stack.stop()
        #expect(!stack.isActive)
        #expect(stack.count == 0)
        stack.start()
        #expect(stack.count == 0)
        #expect(stack.isActive)
    }

    @Test func aRemovedClipLeavesTheStack() {
        var stack = CopyStack()
        stack.start()
        stack.push(1)
        stack.push(2)
        stack.push(1)
        stack.remove(1)
        #expect(stack.count == 1)
        #expect(stack.next() == 2)
    }

    @Test func theOrderIsRememberedInSettings() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.copyStackOrder == .firstCopiedFirst)
        store.copyStackOrder = .lastCopiedFirst
        #expect(ClipboardSettingsStore(defaults: defaults).copyStackOrder == .lastCopiedFirst)
        defaults.set("sideways", forKey: ClipboardSettingsStore.Key.copyStackOrder)
        #expect(store.copyStackOrder == .firstCopiedFirst)
    }
}

@Suite struct PanelAppearanceTests {
    @Test func thePanelFollowsTheSystemUntilToldOtherwise() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.panelAppearance == .system)
        store.panelAppearance = .light
        #expect(ClipboardSettingsStore(defaults: defaults).panelAppearance == .light)
    }

    @Test func anUnknownStoredValueFallsBackToTheSystem() {
        let defaults = InMemoryDefaults()
        defaults.set("sepia", forKey: ClipboardSettingsStore.Key.panelAppearance)
        #expect(ClipboardSettingsStore(defaults: defaults).panelAppearance == .system)
    }

    @Test func resolvesToDarkOrLight() {
        #expect(PanelAppearance.system.isDark(systemIsDark: true) == true)
        #expect(PanelAppearance.system.isDark(systemIsDark: false) == false)
        #expect(PanelAppearance.dark.isDark(systemIsDark: false) == true)
        #expect(PanelAppearance.light.isDark(systemIsDark: true) == false)
    }
}
