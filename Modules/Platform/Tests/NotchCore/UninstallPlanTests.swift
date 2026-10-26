import Foundation
import Testing
@testable import NotchCore

@Suite struct UninstallPlanTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func paths(_ plan: UninstallPlan) -> [String] {
        plan.removals.map(\.path).sorted()
    }

    @Test func everythingTheAppLeftIsTakenAwayWhenTheDataGoesToo() {
        let plan = UninstallPlan(home: home, bundleID: "com.aranotch.app", removesData: true)
        #expect(paths(plan) == [
            "/Users/someone/Library/Application Support/AraNotch",
            "/Users/someone/Library/Caches/com.aranotch.app",
            "/Users/someone/Library/HTTPStorages/com.aranotch.app",
            "/Users/someone/Library/HTTPStorages/com.aranotch.app.binarycookies",
            "/Users/someone/Library/Saved Application State/com.aranotch.app.savedState",
        ])
        #expect(plan.removesSettings)
    }

    @Test func keepingTheDataLeavesTheHistoryAndSettingsButNotTheHookHelper() {
        // Nothing calls the helper once the hooks are gone; the history and the settings are
        // the user's to keep.
        let plan = UninstallPlan(home: home, bundleID: "com.aranotch.app", removesData: false)
        #expect(paths(plan) == [
            "/Users/someone/Library/Application Support/AraNotch/bin",
            "/Users/someone/Library/Caches/com.aranotch.app",
            "/Users/someone/Library/HTTPStorages/com.aranotch.app",
            "/Users/someone/Library/HTTPStorages/com.aranotch.app.binarycookies",
            "/Users/someone/Library/Saved Application State/com.aranotch.app.savedState",
        ])
        #expect(!plan.removesSettings)
    }

    @Test func claudeCodesSettingsAreChangedNotRemoved() {
        let plan = UninstallPlan(home: home, bundleID: "com.aranotch.app", removesData: true)
        #expect(plan.claudeSettings.path == "/Users/someone/.claude/settings.json")
        #expect(!plan.removals.contains { $0.path.hasPrefix("/Users/someone/.claude") })
    }
}
