import Foundation
import Testing
@testable import NotchCore

@Suite struct AppLanguageTests {
    @Test func theChoiceIsReadFromTheAppsOwnLanguageList() {
        #expect(AppLanguage.read(fromAppDomain: nil) == .system)
        #expect(AppLanguage.read(fromAppDomain: [:]) == .system)
        #expect(AppLanguage.read(fromAppDomain: ["AppleLanguages": ["vi"]]) == .vietnamese)
        #expect(AppLanguage.read(fromAppDomain: ["AppleLanguages": ["vi-VN", "en"]]) == .vietnamese)
        #expect(AppLanguage.read(fromAppDomain: ["AppleLanguages": ["en"]]) == .english)
        // A language the app has no words for is the same as following the Mac.
        #expect(AppLanguage.read(fromAppDomain: ["AppleLanguages": ["fr"]]) == .system)
    }

    @Test func choosingALanguageWritesItAndFollowingTheMacTakesItAway() {
        let defaults = InMemoryDefaults()
        AppLanguage.vietnamese.write(to: defaults)
        #expect(defaults.object(forKey: "AppleLanguages") as? [String] == ["vi"])
        AppLanguage.english.write(to: defaults)
        #expect(defaults.object(forKey: "AppleLanguages") as? [String] == ["en"])
        AppLanguage.system.write(to: defaults)
        #expect(defaults.object(forKey: "AppleLanguages") == nil)
    }

    @Test func theAppOpensAgainOnGeneralSettingsKeepingItsOtherArguments() {
        let arguments = ["/Applications/AraNotch.app/Contents/MacOS/AraNotch", "--data-dir", "/tmp/x",
                         "--show-settings", "--settings-tab", "pages", "--open-on-launch"]
        #expect(AppLanguage.relaunchArguments(from: arguments)
            == ["--data-dir", "/tmp/x", "--open-on-launch", "--show-settings", "--settings-tab", "general"])
        #expect(AppLanguage.relaunchArguments(from: ["/x/AraNotch"]) == ["--show-settings", "--settings-tab", "general"])
    }
}
