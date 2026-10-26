import Foundation
import Testing
@testable import TranslateCore

@Suite struct GoogleTranslateRequestTests {
    @Test func sendsTheTextInTheBodyNotInTheAddress() throws {
        let request = try #require(GoogleTranslate.request(text: "Xin chào & tạm biệt?", target: "en"))
        #expect(request.httpMethod == "POST")
        let url = try #require(request.url)
        #expect(url.host == "translate.googleapis.com")
        #expect(url.path == "/translate_a/single")
        #expect(url.query == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")

        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        let fields = Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? parts[1].removingPercentEncoding ?? "" : "")
        })
        #expect(fields["client"] == "gtx")
        #expect(fields["sl"] == "auto")
        #expect(fields["tl"] == "en")
        #expect(fields["dt"] == "t")
        #expect(fields["q"] == "Xin chào & tạm biệt?")
        // The ampersand and question mark of the text must not break the form.
        #expect(!body.contains("& tạm"))
    }

    @Test func refusesEmptyAndOverlongText() {
        #expect(GoogleTranslate.request(text: "  \n ", target: "vi") == nil)
        #expect(GoogleTranslate.request(text: String(repeating: "a", count: GoogleTranslate.maxLength + 1), target: "vi") == nil)
        #expect(GoogleTranslate.request(text: String(repeating: "a", count: GoogleTranslate.maxLength), target: "vi") != nil)
    }
}

@Suite struct GoogleTranslateResponseTests {
    @Test func joinsTheTranslatedSentencesAndReadsTheSourceLanguage() throws {
        let json = #"[[["Xin chào. ","Hello. ",null,null,10],["Bạn khỏe không?","How are you?",null,null,3]],null,"en",null,null,null,1,[],[["en"],null,[1],["en"]]]"#
        let result = try #require(GoogleTranslate.parse(Data(json.utf8)))
        #expect(result.text == "Xin chào. Bạn khỏe không?")
        #expect(result.sourceLanguage == "en")
    }

    @Test func skipsPartsThatCarryNoTranslation() throws {
        // The last element of the sentence list is often a transliteration entry without text.
        let json = #"[[["こんにちは","Hello",null,null,1],[null,null,"Kon'nichiwa"]],null,"en"]"#
        let result = try #require(GoogleTranslate.parse(Data(json.utf8)))
        #expect(result.text == "こんにちは")
    }

    @Test(arguments: ["", "<html>blocked</html>", "{}", "[]", "[null,null,\"en\"]", "[[],null,\"en\"]"])
    func anythingElseIsNoResult(_ body: String) {
        #expect(GoogleTranslate.parse(Data(body.utf8)) == nil)
    }
}

@Suite struct TranslationPlanTests {
    @Test func foreignTextGoesToTheMainLanguage() {
        let plan = TranslationPlan(target: "vi", alternate: "en")
        #expect(plan.firstTarget == "vi")
        #expect(plan.retryTarget(detectedSource: "en") == nil)
        #expect(plan.retryTarget(detectedSource: "ja") == nil)
    }

    @Test func textAlreadyInTheMainLanguageGoesToTheOther() {
        let plan = TranslationPlan(target: "vi", alternate: "en")
        #expect(plan.retryTarget(detectedSource: "vi") == "en")
        // Regional variants count as the same language.
        #expect(TranslationPlan(target: "zh-CN", alternate: "en").retryTarget(detectedSource: "zh-TW") == "en")
    }

    @Test func withoutAnotherLanguageThereIsNoRetry() {
        #expect(TranslationPlan(target: "vi", alternate: nil).retryTarget(detectedSource: "vi") == nil)
        #expect(TranslationPlan(target: "vi", alternate: "vi").retryTarget(detectedSource: "vi") == nil)
    }
}

@Suite struct TranslateSettingsStoreTests {
    @Test func defaultsFollowTheOwnersChoice() {
        let store = TranslateSettingsStore(defaults: InMemoryDefaults())
        // Off until switched on: it claims a global shortcut and sends text to Google.
        #expect(store.isEnabled == false)
        #expect(store.target == "vi")
        #expect(store.alternate == "en")
    }

    @Test func choicesAreRemembered() {
        let defaults = InMemoryDefaults()
        let store = TranslateSettingsStore(defaults: defaults)
        store.isEnabled = true
        store.target = "en"
        store.alternate = nil
        let reopened = TranslateSettingsStore(defaults: defaults)
        #expect(reopened.isEnabled == true)
        #expect(reopened.target == "en")
        #expect(reopened.alternate == nil)
    }

    @Test func unknownLanguagesFallBack() {
        let defaults = InMemoryDefaults()
        defaults.set("klingon", forKey: TranslateSettingsStore.Key.target)
        #expect(TranslateSettingsStore(defaults: defaults).target == "vi")
        #expect(TranslateLanguage.all.map(\.code).contains("vi"))
        #expect(TranslateLanguage.all.count >= 8)
    }
}

@Suite struct TranslationSwapTests {
    @Test func theOtherLanguageOfThePairIsOfferedForASwap() {
        let plan = TranslationPlan(target: "vi", alternate: "en")
        #expect(plan.swapTarget(from: "vi") == "en")
        #expect(plan.swapTarget(from: "en") == "vi")
    }

    @Test func aLanguageOutsideThePairSwapsBackToTheMainOne() {
        let plan = TranslationPlan(target: "vi", alternate: "en")
        #expect(plan.swapTarget(from: "ja") == "vi")
    }

    @Test func withNoSecondLanguageThereIsNothingToSwapTo() {
        #expect(TranslationPlan(target: "vi", alternate: nil).swapTarget(from: "vi") == nil)
        #expect(TranslationPlan(target: "vi", alternate: "vi").swapTarget(from: "vi") == nil)
        // From another language there is still the main one to go back to.
        #expect(TranslationPlan(target: "vi", alternate: nil).swapTarget(from: "ja") == "vi")
    }

    @Test func aSwapBackIntoTheLanguageTheTextIsWrittenInIsNotOffered() {
        let plan = TranslationPlan(target: "vi", alternate: "en")
        // English text shown in Vietnamese: English again would change nothing.
        #expect(plan.swapTarget(from: "vi", source: "en") == nil)
        #expect(plan.swapTarget(from: "vi", source: "en-US") == nil)
        // Chinese text shown in Vietnamese can still go to English.
        #expect(plan.swapTarget(from: "vi", source: "zh-CN") == "en")
        #expect(plan.swapTarget(from: "vi", source: nil) == "en")
    }

    @Test func theVoiceForALanguageIsItsRegionalCode() {
        #expect(TranslateLanguage.voiceCode(for: "vi") == "vi-VN")
        #expect(TranslateLanguage.voiceCode(for: "en") == "en-US")
        #expect(TranslateLanguage.voiceCode(for: "zh-CN") == "zh-CN")
        #expect(TranslateLanguage.voiceCode(for: "ja") == "ja-JP")
        // A language with no usual region is passed as it is.
        #expect(TranslateLanguage.voiceCode(for: "xx") == "xx")
    }
}
