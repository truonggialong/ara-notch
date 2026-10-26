import Testing
@testable import ClipboardCore

@Suite struct SearchFoldingTests {
    @Test func foldLowercasesAndStripsDiacritics() {
        #expect(SearchFolding.fold("Đường DẪN Tiếng Việt") == "duong dan tieng viet")
    }
}

@Suite struct ClipQueryParsingTests {
    @Test func plainTextQuery() {
        let query = ClipQuery("hello world")
        #expect(query.kind == nil)
        #expect(query.app == nil)
        #expect(query.text == "hello world")
    }

    @Test func kindFilter() {
        let query = ClipQuery("@image")
        #expect(query.kind == .image)
        #expect(query.text == "")
        #expect(!query.isEmpty)
    }

    @Test(arguments: [("@ảnh", ClipKind.image), ("@anh", .image), ("@màu", .color), ("@tệp", .file), ("@chữ", .text), ("@Ảnh", .image)])
    func kindFilterInVietnamese(_ word: String, _ kind: ClipKind) {
        #expect(ClipQuery(word).kind == kind)
        #expect(ClipQuery(word).app == nil)
    }

    @Test func kindFilterIsCaseInsensitive() {
        #expect(ClipQuery("@IMAGE").kind == .image)
    }

    @Test func appFilter() {
        let query = ClipQuery("@chrome báo cáo")
        #expect(query.kind == nil)
        #expect(query.app == "chrome")
        #expect(query.text == "báo cáo")
    }

    @Test func lastFilterOfEachTypeWins() {
        let query = ClipQuery("@link @image @safari @chrome x")
        #expect(query.kind == .image)
        #expect(query.app == "chrome")
        #expect(query.text == "x")
    }

    @Test func loneAtSignIsIgnored() {
        let query = ClipQuery("@ abc")
        #expect(query.kind == nil)
        #expect(query.app == nil)
        #expect(query.text == "abc")
    }

    @Test func whitespaceCollapses() {
        #expect(ClipQuery("  a   b  ").text == "a b")
    }

    @Test func emptyQueryIsEmpty() {
        #expect(ClipQuery("").isEmpty)
        #expect(ClipQuery("   ").isEmpty)
    }
}

@Suite struct ClipQueryMatchingTests {
    @Test func emptyQueryMatchesEverything() {
        #expect(ClipQuery("").matches(makeItem(kind: .image)))
        #expect(ClipQuery("").matches(makeItem(text: "anything")))
    }

    @Test func textMatchIgnoresCaseAndDiacritics() {
        let item = makeItem(text: "Đường về nhà")
        #expect(ClipQuery("duong").matches(item))
        #expect(ClipQuery("VỀ NHÀ").matches(item))
        #expect(!ClipQuery("xyz").matches(item))
    }

    @Test func kindMatch() {
        #expect(ClipQuery("@link").matches(makeItem(kind: .link, text: "https://a.com")))
        #expect(!ClipQuery("@link").matches(makeItem(kind: .text, text: "https")))
    }

    @Test func appMatchUsesNameOrBundleID() {
        #expect(ClipQuery("@zalo").matches(makeItem(appName: "Zalo")))
        #expect(ClipQuery("@google").matches(makeItem(appName: "Chrome", bundleID: "com.google.Chrome")))
        #expect(!ClipQuery("@zalo").matches(makeItem(appName: "Notes")))
        #expect(!ClipQuery("@zalo").matches(makeItem()))
    }

    @Test func filtersCombine() {
        let query = ClipQuery("@text @notes họp")
        #expect(query.matches(makeItem(kind: .text, text: "Lịch họp tuần", appName: "Notes")))
        #expect(!query.matches(makeItem(kind: .link, text: "họp", appName: "Notes")))
        #expect(!query.matches(makeItem(kind: .text, text: "Lịch họp tuần", appName: "Safari")))
        #expect(!query.matches(makeItem(kind: .text, text: "khác", appName: "Notes")))
    }
}
