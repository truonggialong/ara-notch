import Testing
@testable import ClipboardCore

@Suite struct TextTransformTests {
    // MARK: Cleanup

    @Test func trimStripsEachLineAndTheBlankLinesAroundTheText() {
        #expect(TextTransform.trimWhitespace.apply(to: "\n\n  xin chào \t\n\n   bạn  \n \n") == "xin chào\n\nbạn")
    }

    @Test func removeEmptyLinesDropsBlankAndWhitespaceOnlyLines() {
        #expect(TextTransform.removeEmptyLines.apply(to: "a\n\n  \n  b\n\t\nc\n") == "a\n  b\nc")
    }

    @Test func joinLinesPutsTheLinesOnOneLineSeparatedBySingleSpaces() {
        #expect(TextTransform.joinLines.apply(to: "Hạn nộp:\n   thứ Sáu \n\ntuần này") == "Hạn nộp: thứ Sáu tuần này")
    }

    @Test func sortLinesIgnoresCaseAndOrdersNumbersByValue() {
        #expect(TextTransform.sortLines.apply(to: "mục 10\nchuối\nMục 2\nAn") == "An\nchuối\nMục 2\nmục 10")
    }

    @Test func uniqueLinesKeepsTheFirstOfEachLineInOrder() {
        #expect(TextTransform.uniqueLines.apply(to: "b\na\nb\nB\na\nc") == "b\na\nB\nc")
    }

    @Test func windowsLineEndingsAreUnderstood() {
        #expect(TextTransform.uniqueLines.apply(to: "a\r\nb\r\na") == "a\nb")
    }

    // MARK: Letter case

    @Test func letterCaseHandlesVietnamese() {
        #expect(TextTransform.uppercase.apply(to: "Đường về nhà") == "ĐƯỜNG VỀ NHÀ")
        #expect(TextTransform.lowercase.apply(to: "ĐƯỜNG Về Nhà") == "đường về nhà")
        #expect(TextTransform.titleCase.apply(to: "đường VỀ nhà\nisn't it") == "Đường Về Nhà\nIsn't It")
    }

    // MARK: Naming styles

    @Test(arguments: [
        ("user profile image", "userProfileImage", "user_profile_image", "user-profile-image"),
        ("UserProfileImage", "userProfileImage", "user_profile_image", "user-profile-image"),
        ("user_profile-image", "userProfileImage", "user_profile_image", "user-profile-image"),
        ("HTTPServerError", "httpServerError", "http_server_error", "http-server-error"),
        ("parseURL2Fast", "parseUrl2Fast", "parse_url2_fast", "parse-url2-fast"),
        ("  Xin chào, bạn!  ", "xinChàoBạn", "xin_chào_bạn", "xin-chào-bạn"),
    ])
    func namingStyles(_ sample: (String, String, String, String)) {
        #expect(TextTransform.camelCase.apply(to: sample.0) == sample.1)
        #expect(TextTransform.snakeCase.apply(to: sample.0) == sample.2)
        #expect(TextTransform.kebabCase.apply(to: sample.0) == sample.3)
    }

    @Test func namingStylesConvertEachLineSeparately() {
        #expect(TextTransform.snakeCase.apply(to: "firstName\n\nlastName") == "first_name\n\nlast_name")
    }

    @Test func namingStylesNeedAtLeastOneLetterOrDigit() {
        #expect(TextTransform.camelCase.apply(to: " -- ") == nil)
    }

    // MARK: JSON

    @Test func prettyJSONIndentsAndKeepsKeyOrderAndNumberSpelling() {
        let source = #"{"b":1.50,"a":[1,2,{"c":null}],"e":{},"f":[ ],"s":"x, {y}: \"z\""}"#
        let expected = """
        {
          "b": 1.50,
          "a": [
            1,
            2,
            {
              "c": null
            }
          ],
          "e": {},
          "f": [],
          "s": "x, {y}: \\"z\\""
        }
        """
        #expect(TextTransform.prettyJSON.apply(to: source) == expected)
    }

    @Test func minifyJSONRemovesWhitespaceOutsideStrings() {
        let source = "{\n  \"name\" : \"Ara Notch\",\n  \"tags\" : [ 1, 2 ]\n}\n"
        #expect(TextTransform.minifyJSON.apply(to: source) == #"{"name":"Ara Notch","tags":[1,2]}"#)
    }

    @Test(arguments: ["", "xin chào", "{\"a\": }", "{'a': 1}", "[1, 2"])
    func jsonToolsRejectInvalidJSON(_ text: String) {
        #expect(TextTransform.prettyJSON.apply(to: text) == nil)
        #expect(TextTransform.minifyJSON.apply(to: text) == nil)
    }

    // MARK: Encoding

    @Test func base64RoundTripsUnicode() {
        #expect(TextTransform.base64Encode.apply(to: "Xin chào") == "WGluIGNow6Bv")
        #expect(TextTransform.base64Decode.apply(to: "WGluIGNow6Bv") == "Xin chào")
    }

    @Test func base64DecodeAcceptsLineBreaksURLSafeAlphabetAndMissingPadding() {
        #expect(TextTransform.base64Decode.apply(to: " WGluIGNo\nw6Bv \n") == "Xin chào")
        // "??>>" is "Pz8+Pg==" in the standard alphabet.
        #expect(TextTransform.base64Decode.apply(to: "Pz8-Pg") == "??>>")
    }

    @Test(arguments: ["", "xin chào", "!!!!", "/w=="])
    func base64DecodeRejectsWhatIsNotBase64Text(_ text: String) {
        #expect(TextTransform.base64Decode.apply(to: text) == nil)
    }

    @Test func urlEncodingEscapesEverythingButUnreservedCharacters() {
        #expect(TextTransform.urlEncode.apply(to: "a b&c=d/é~x-1_2.3") == "a%20b%26c%3Dd%2F%C3%A9~x-1_2.3")
        #expect(TextTransform.urlDecode.apply(to: "a%20b%26c%3Dd%2F%C3%A9") == "a b&c=d/é")
    }

    @Test func urlDecodeRejectsBrokenEscapes() {
        #expect(TextTransform.urlDecode.apply(to: "100%zz") == nil)
    }

    // MARK: Catalogue

    @Test func everyToolBelongsToOneGroupAndGroupsKeepMenuOrder() {
        let grouped = TextTransform.Group.allCases.flatMap(TextTransform.tools(in:))
        #expect(grouped == TextTransform.allCases)
        #expect(TextTransform.allCases.count == 17)
    }

    @Test func emptyTextCannotBeTransformed() {
        for tool in TextTransform.allCases {
            #expect(tool.apply(to: "") == nil)
            #expect(tool.apply(to: " \n ") == nil)
        }
    }
}
