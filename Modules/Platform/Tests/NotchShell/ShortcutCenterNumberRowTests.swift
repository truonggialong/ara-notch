import NotchCore
import Testing
@testable import NotchShell

private let pinned = NumberRow(storageKey: "test.pinnedModifiers", titleKey: "pinned", noteKey: "pinned.note")
private let recent = NumberRow(storageKey: "test.recentModifiers", titleKey: "recent", noteKey: "recent.note")

@MainActor
@Suite struct ShortcutCenterNumberRowTests {
    /// A center whose rows were declared by features; recording keeps it from taking real keys.
    private func center() -> ShortcutCenter {
        let center = ShortcutCenter(store: ShortcutStore(defaults: InMemoryDefaults()))
        center.isRecording = true
        center.setNumberRow(pinned) { _ in }
        center.setNumberRow(recent) { _ in }
        return center
    }

    @Test func aRowCannotTakeTheModifiersAnotherDeclaredRowHas() {
        let center = center()
        center.setModifiers([.control, .option], for: pinned)
        center.setModifiers([.control, .option], for: recent)
        #expect(center.numberRowModifiers[pinned] == [.control, .option])
        #expect(center.numberRowModifiers[recent] == nil)
    }

    @Test func theRowUsingACombinationIsFoundAmongTheDeclaredRows() {
        let center = center()
        center.setModifiers([.control, .command], for: recent)
        #expect(center.numberRow(using: KeyCombo(keyCode: 18, modifiers: [.control, .command])) == recent)
        #expect(center.numberRow(using: KeyCombo(keyCode: 18, modifiers: [.control, .option])) == nil)
    }
}
