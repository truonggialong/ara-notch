import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct KeyComboTests {
    @Test func aComboNeedsCommandControlOrOption() {
        #expect(KeyCombo(keyCode: 8, modifiers: [.command, .shift]).isValid)
        #expect(KeyCombo(keyCode: 8, modifiers: [.control]).isValid)
        #expect(KeyCombo(keyCode: 8, modifiers: [.option]).isValid)
        // Shift alone, or nothing, would take a key people type with.
        #expect(!KeyCombo(keyCode: 8, modifiers: [.shift]).isValid)
        #expect(!KeyCombo(keyCode: 8, modifiers: []).isValid)
    }

    @Test func functionKeysWorkOnTheirOwn() {
        // F5 has key code 96.
        #expect(KeyCombo(keyCode: 96, modifiers: []).isValid)
        #expect(KeyCombo(keyCode: 122, modifiers: [.shift]).isValid)
    }

    @Test func survivesBeingStoredAsText() {
        let combo = KeyCombo(keyCode: 42, modifiers: [.shift, .option])
        #expect(KeyCombo(storage: combo.storage) == combo)
        #expect(KeyCombo(storage: "") == nil)
        #expect(KeyCombo(storage: "nonsense") == nil)
        #expect(KeyCombo(storage: "99:x") == nil)
    }

    @Test func listsItsModifierSymbolsInTheUsualOrder() {
        #expect(KeyCombo(keyCode: 8, modifiers: [.command, .shift, .control, .option]).modifierSymbols == "⌃⌥⇧⌘")
        #expect(KeyCombo(keyCode: 8, modifiers: [.command]).modifierSymbols == "⌘")
    }
}

@Suite struct ShortcutStoreTests {
    @Test func startsWithTheShortcutsTheAppAlwaysHad() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        #expect(store.combo(for: .clipboardPanel) == KeyCombo(keyCode: 8, modifiers: [.command, .shift]))
        #expect(store.combo(for: .translate) == KeyCombo(keyCode: 5, modifiers: [.command, .shift]))
        #expect(store.combo(for: .captureRegion) == KeyCombo(keyCode: 19, modifiers: [.command, .shift]))
        #expect(store.combo(for: .openNotch) == nil)
        #expect(store.combo(for: .hideNotch) == nil)
    }

    @Test func aShortcutCanBeChanged() {
        let defaults = InMemoryDefaults()
        let store = ShortcutStore(defaults: defaults)
        let combo = KeyCombo(keyCode: 9, modifiers: [.control, .option])
        store.set(combo, for: .clipboardPanel)
        #expect(ShortcutStore(defaults: defaults).combo(for: .clipboardPanel) == combo)
    }

    @Test func aShortcutCanBeRemovedAndStaysRemoved() {
        let defaults = InMemoryDefaults()
        let store = ShortcutStore(defaults: defaults)
        store.set(nil, for: .translate)
        // Removed is not the same as never set: the default must not come back.
        #expect(ShortcutStore(defaults: defaults).combo(for: .translate) == nil)
    }

    @Test func aShortcutCanGoBackToItsDefault() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        store.set(nil, for: .translate)
        store.reset(.translate)
        #expect(store.combo(for: .translate) == KeyCombo(keyCode: 5, modifiers: [.command, .shift]))
    }

    @Test func knowsWhenAShortcutIsNoLongerItsDefault() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        #expect(!store.differsFromDefault(.translate))
        #expect(!store.differsFromDefault(.newNote))
        store.set(nil, for: .translate)
        store.set(KeyCombo(keyCode: 38, modifiers: [.control, .option]), for: .newNote)
        #expect(store.differsFromDefault(.translate))
        #expect(store.differsFromDefault(.newNote))
        store.reset(.translate)
        // A shortcut removed where the default is also none is the default again.
        store.set(nil, for: .newNote)
        #expect(!store.differsFromDefault(.translate))
        #expect(!store.differsFromDefault(.newNote))
    }

    @Test func tellsWhichActionAlreadyUsesACombo() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        let taken = KeyCombo(keyCode: 5, modifiers: [.command, .shift])
        #expect(store.action(using: taken, otherThan: .clipboardPanel) == .translate)
        // An action does not conflict with itself.
        #expect(store.action(using: taken, otherThan: .translate) == nil)
        #expect(store.action(using: KeyCombo(keyCode: 0, modifiers: [.control]), otherThan: .translate) == nil)
    }

    @Test func invalidCombosAreNotStored() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        store.set(KeyCombo(keyCode: 8, modifiers: [.shift]), for: .openNotch)
        #expect(store.combo(for: .openNotch) == nil)
    }
}

/// Two rows as the clipboard declares them: pinned clips and the newest clips.
private let pinned = NumberRow(storageKey: "shortcut.quickPasteModifiers", titleKey: "pinned", noteKey: "pinned.note")
private let recent = NumberRow(storageKey: "shortcut.recentPasteModifiers", titleKey: "recent", noteKey: "recent.note")

@Suite struct NumberRowShortcutTests {
    @Test func aRowIsOffUntilAModifierIsChosen() {
        let defaults = InMemoryDefaults()
        let store = ShortcutStore(defaults: defaults)
        #expect(store.modifiers(for: pinned) == nil)
        #expect(store.combos(for: pinned).isEmpty)
        store.setModifiers([.control, .option], for: pinned, others: [recent])
        #expect(ShortcutStore(defaults: defaults).modifiers(for: pinned) == [.control, .option])
        #expect(defaults.object(forKey: "shortcut.quickPasteModifiers") as? Int == KeyComboModifiers([.control, .option]).rawValue)
        store.setModifiers(nil, for: pinned, others: [recent])
        #expect(ShortcutStore(defaults: defaults).modifiers(for: pinned) == nil)
    }

    @Test func theNineCombosUseTheDigitKeys() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        store.setModifiers([.control], for: pinned, others: [])
        let combos = store.combos(for: pinned)
        #expect(combos.count == 9)
        // The top-row digits are not in key code order: 1 is 18, 5 is 23, 6 is 22.
        #expect(combos[0] == KeyCombo(keyCode: 18, modifiers: [.control]))
        #expect(combos[4] == KeyCombo(keyCode: 23, modifiers: [.control]))
        #expect(combos[5] == KeyCombo(keyCode: 22, modifiers: [.control]))
    }

    @Test func aModifierThatIsOnlyShiftIsRefused() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        store.setModifiers([.shift], for: pinned, others: [recent])
        #expect(store.modifiers(for: pinned) == nil)
        #expect(store.combos(for: pinned).isEmpty)
    }

    @Test func aSecondRowReadsItsOwnKey() {
        let defaults = InMemoryDefaults()
        let store = ShortcutStore(defaults: defaults)
        store.setModifiers([.control, .command], for: recent, others: [pinned])
        #expect(ShortcutStore(defaults: defaults).modifiers(for: recent) == [.control, .command])
        #expect(store.modifiers(for: pinned) == nil)
        #expect(store.combos(for: recent).first == KeyCombo(keyCode: 18, modifiers: [.control, .command]))
        #expect(store.combos(for: recent).count == 9)
    }

    @Test func twoRowsCannotShareTheirModifiers() {
        let store = ShortcutStore(defaults: InMemoryDefaults())
        store.setModifiers([.control, .option], for: pinned, others: [recent])
        store.setModifiers([.control, .option], for: recent, others: [pinned])
        // The second to ask for the same keys is refused.
        #expect(store.modifiers(for: recent) == nil)
        store.setModifiers([.control, .shift], for: recent, others: [pinned])
        store.setModifiers([.control, .shift], for: pinned, others: [recent])
        #expect(store.modifiers(for: pinned) == [.control, .option])
    }
}

@Suite struct NotchSizeTests {
    @Test func theSizeInUseIsAQuarterLargerThanTheLayoutIsDrawnAt() {
        // Pages are laid out on a 640 by 200 sheet and shown enlarged, text and icons with it.
        // A fifth larger was the usual size until the sizes became four (0.23.0).
        #expect(NotchGeometry.defaultOpenSize == CGSize(width: 640, height: 200))
        #expect(NotchSize.standard == .large)
        #expect(NotchSize.large.scale == 1.25)
        #expect(NotchSize.large.openSize == CGSize(width: 800, height: 250))
    }

    @Test func thereAreFourSizes() {
        #expect(NotchSize.allCases == [.compact, .regular, .large, .extraLarge])
        #expect(NotchSize.compact.scale == 1)
        #expect(NotchSize.compact.openSize == CGSize(width: 640, height: 200))
        #expect(NotchSize.regular.scale == 1.1)
        #expect(NotchSize.regular.openSize == CGSize(width: 704, height: 220))
        #expect(NotchSize.extraLarge.scale == 1.5)
        #expect(NotchSize.extraLarge.openSize == CGSize(width: 960, height: 300))
    }

    @Test func theTabRowAndTheActivitiesGrowOnlyAsFarAsTheNotchIsTall() {
        // Both sit beside the hardware notch, 32 points high whatever the size chosen.
        #expect(NotchSize.compact.edgeScale == 1)
        #expect(NotchSize.regular.edgeScale == 1.1)
        #expect(NotchSize.large.edgeScale == 1.25)
        #expect(NotchSize.extraLarge.edgeScale == 1.3)
        #expect(NotchSize.regular.activitySideWidth == 101)
    }

    @Test func theChosenSizeIsRememberedAndNonsenseReadsAsTheUsualSize() {
        let defaults = InMemoryDefaults()
        let store = ShellSettingsStore(defaults: defaults)
        #expect(store.notchSize == .large)
        store.notchSize = .extraLarge
        #expect(ShellSettingsStore(defaults: defaults).notchSize == .extraLarge)
        defaults.set("nonsense", forKey: ShellSettingsStore.Key.notchSize)
        #expect(ShellSettingsStore(defaults: defaults).notchSize == .large)
        // A size chosen before the usual one changed stays the one chosen.
        defaults.set("regular", forKey: ShellSettingsStore.Key.notchSize)
        #expect(ShellSettingsStore(defaults: defaults).notchSize == .regular)
    }

    @Test func theFifthLargerSizeOfOlderVersionsReadsAsTheQuarterLargerOne() {
        let defaults = InMemoryDefaults()
        defaults.set("comfortable", forKey: ShellSettingsStore.Key.notchSize)
        #expect(ShellSettingsStore(defaults: defaults).notchSize == .large)
    }

    @Test func aNewNoteHasAShortcutSlotWithNoKeysYet() {
        #expect(ShortcutStore(defaults: InMemoryDefaults()).combo(for: .newNote) == nil)
    }
}
