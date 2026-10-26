import Combine
import OverviewCore
import Testing
@testable import OverviewFeature

@MainActor
@Suite struct OverviewEditorTests {
    private func editor() -> OverviewEditor {
        OverviewEditor(settings: OverviewSettings(store: OverviewSettingsStore(defaults: InMemoryDefaults())))
    }

    @Test func editingEndsWhenTheNotchCloses() {
        let editor = editor()
        let isOpen = PassthroughSubject<Bool, Never>()
        var told: [Bool] = []
        editor.connect(isOpen: isOpen.eraseToAnyPublisher(), selectedPage: Empty().eraseToAnyPublisher()) { told.append($0) }
        editor.begin()
        isOpen.send(false)
        #expect(!editor.isEditing)
        #expect(told == [true, false])
    }

    @Test func editingEndsWhenAnotherPageShows() {
        let editor = editor()
        let page = PassthroughSubject<String?, Never>()
        editor.connect(isOpen: Empty().eraseToAnyPublisher(), selectedPage: page.eraseToAnyPublisher()) { _ in }
        editor.begin()
        page.send(OverviewLayout.pageID)
        #expect(editor.isEditing)
        page.send("clipboard")
        #expect(!editor.isEditing)
    }

    /// Connecting again replaces the earlier links instead of adding to them.
    @Test func aSecondConnectionReplacesTheFirst() {
        let editor = editor()
        let first = PassthroughSubject<Bool, Never>()
        let second = PassthroughSubject<Bool, Never>()
        var toldFirst: [Bool] = []
        var toldSecond: [Bool] = []
        editor.connect(isOpen: first.eraseToAnyPublisher(), selectedPage: Empty().eraseToAnyPublisher()) { toldFirst.append($0) }
        editor.connect(isOpen: second.eraseToAnyPublisher(), selectedPage: Empty().eraseToAnyPublisher()) { toldSecond.append($0) }
        editor.begin()
        first.send(false)
        #expect(editor.isEditing)
        second.send(false)
        #expect(!editor.isEditing)
        #expect(toldFirst.isEmpty)
        #expect(toldSecond == [true, false])
    }
}
