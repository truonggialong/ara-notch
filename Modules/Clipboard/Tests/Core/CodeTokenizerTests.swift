import Testing
@testable import ClipboardCore

/// Token kinds with their trimmed text, skipping whitespace-only tokens.
private func tokens(_ text: String) -> [CodeToken] {
    CodeTokenizer.tokenize(text)
        .map { CodeToken(kind: $0.kind, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .filter { !$0.text.isEmpty }
}

private func token(_ kind: CodeToken.Kind, _ text: String) -> CodeToken {
    CodeToken(kind: kind, text: text)
}

@Suite struct CodeTokenizerTests {
    @Test func keywordPlainAndNumber() {
        #expect(tokens("let x = 42") == [token(.keyword, "let"), token(.plain, "x ="), token(.number, "42")])
    }

    @Test func stringWithEscapedQuotesIsOneToken() {
        #expect(tokens(#""a \"b\" c""#) == [token(.string, #""a \"b\" c""#)])
    }

    @Test func singleQuotedAndBacktickStrings() {
        #expect(tokens("'a' `b`") == [token(.string, "'a'"), token(.string, "`b`")])
    }

    @Test func lineCommentSwallowsQuotes() {
        let text = #"// chú thích "không phải chuỗi""#
        #expect(tokens(text) == [token(.comment, text)])
    }

    @Test func lineCommentEndsAtNewline() {
        #expect(tokens("x // note\ny") == [token(.plain, "x"), token(.comment, "// note"), token(.plain, "y")])
    }

    @Test func blockCommentSpansLines() {
        #expect(tokens("/* a\nb */ x") == [token(.comment, "/* a\nb */"), token(.plain, "x")])
    }

    @Test func hashStartsACommentOnlyAtLineStart() {
        #expect(tokens("  # ghi chú") == [token(.comment, "# ghi chú")])
        #expect(!tokens("color = #fff").contains { $0.kind == .comment })
    }

    @Test func doubleDashStartsACommentOnlyAtLineStart() {
        #expect(tokens("-- ghi chú") == [token(.comment, "-- ghi chú")])
        #expect(!tokens("a -- b").contains { $0.kind == .comment })
    }

    @Test(arguments: ["0xFF", "3.14", "1_000", "7"])
    func numbers(_ text: String) {
        #expect(tokens(text) == [token(.number, text)])
    }

    @Test func digitsInsideIdentifiersAreNotNumbers() {
        #expect(tokens("abc123") == [token(.plain, "abc123")])
    }

    @Test func keywordMustBeAWholeWord() {
        #expect(tokens("return") == [token(.keyword, "return")])
        #expect(tokens("returned") == [token(.plain, "returned")])
    }

    @Test func unterminatedStringStopsAtEndOfLine() {
        #expect(tokens("\"abc\nnext") == [token(.string, "\"abc"), token(.plain, "next")])
    }

    @Test func unterminatedBlockCommentRunsToTheEnd() {
        #expect(tokens("/* không đóng") == [token(.comment, "/* không đóng")])
    }

    @Test func trailingBackslashInStringDoesNotCrash() {
        #expect(tokens(#""abc\"#) == [token(.string, #""abc\"#)])
    }

    @Test func emptyTextHasNoTokens() {
        #expect(CodeTokenizer.tokenize("").isEmpty)
    }

    @Test func adjacentPlainTokensAreMerged() {
        #expect(CodeTokenizer.tokenize("a + b").count == 1)
    }

    @Test(arguments: [
        "", "   \n\t ", "let x = 42", "func greet(_ name: String) -> String {\n    \"Xin chào, \\(name)!\"\n}",
        "// chú thích tiếng Việt 🎉\nlet s = \"đường 🚀\"", "/* không đóng", "\"abc\\", "'", "a -- b # c // d /* e */",
        "x = 0x1F + 3.14 - 1_000 * abc123", "👨‍👩‍👧‍👦 = \"gia đình\" // emoji ghép",
    ])
    func tokensCoverTheWholeText(_ text: String) {
        #expect(CodeTokenizer.tokenize(text).map(\.text).joined() == text)
    }
}
