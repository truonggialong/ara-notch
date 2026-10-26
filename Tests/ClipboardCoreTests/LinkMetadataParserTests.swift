import Foundation
import Testing
@testable import ClipboardCore

private let base = URL(string: "https://example.com/tin/bai.html")!

private func parse(_ html: String) -> LinkMetadata {
    LinkMetadataParser.parse(html: html, baseURL: base)
}

@Suite struct LinkMetadataTitleTests {
    @Test func ogTitleWinsOverTitleTag() {
        let html = #"<title>Thẻ title</title><meta property="og:title" content="Tiêu đề OG">"#
        #expect(parse(html).title == "Tiêu đề OG")
    }

    @Test func twitterTitleIsSecondChoice() {
        let html = #"<title>Thẻ title</title><meta name="twitter:title" content="Tiêu đề Twitter">"#
        #expect(parse(html).title == "Tiêu đề Twitter")
    }

    @Test func titleTagIsTheFallback() {
        #expect(parse("<html><head><title>Chỉ có title</title></head></html>").title == "Chỉ có title")
    }

    @Test func titleTagWithAttributes() {
        #expect(parse(#"<title data-rh="true">Có thuộc tính</title>"#).title == "Có thuộc tính")
    }

    @Test func entitiesAreDecoded() {
        let html = "<title>Tom &amp; Jerry &#8211; &quot;Phim&quot; &#x1F600;&nbsp;hay &lt;3 &apos;ok&#39;</title>"
        #expect(parse(html).title == "Tom & Jerry – \"Phim\" 😀 hay <3 'ok'")
    }

    @Test func unknownEntitiesAreLeftAlone() {
        #expect(parse("<title>A &bogus; B &amp C</title>").title == "A &bogus; B &amp C")
    }

    @Test func whitespaceIsCollapsed() {
        #expect(parse("<title>\n    Dòng một\n\t  dòng hai   \n</title>").title == "Dòng một dòng hai")
    }

    @Test func titleIsTruncatedTo200Characters() {
        let long = String(repeating: "á", count: 500)
        #expect(parse("<title>\(long)</title>").title?.count == 200)
    }

    @Test func blankTitleIsNil() {
        #expect(parse("<title>   \n </title>").title == nil)
        #expect(parse(#"<meta property="og:title" content="">"#).title == nil)
    }

    @Test func blankOGTitleFallsBackToTitleTag() {
        #expect(parse(#"<meta property="og:title" content=" "><title>Dự phòng</title>"#).title == "Dự phòng")
    }

    @Test func noTagsGivesEmptyMetadata() {
        #expect(parse("just text, no tags") == LinkMetadata())
        #expect(parse("") == LinkMetadata())
    }

    @Test func unclosedTitleTagIsIgnored() {
        #expect(parse("<title>abc").title == nil)
    }

    @Test func attributeOrderAndQuotesDoNotMatter() {
        #expect(parse("<meta content='Tiêu đề' property='og:title'>").title == "Tiêu đề")
        #expect(parse(#"<meta name="og:title" content="X">"#).title == "X")
        #expect(parse(#"<meta   property = "og:title"   content = "Có khoảng trắng" />"#).title == "Có khoảng trắng")
    }

    @Test func tagsAreCaseInsensitive() {
        #expect(parse("<TITLE>Hoa</TITLE>").title == "Hoa")
        #expect(parse(#"<META PROPERTY="OG:TITLE" CONTENT="Hoa OG">"#).title == "Hoa OG")
    }

    @Test func contentMayContainTheOtherQuote() {
        #expect(parse(#"<meta property="og:title" content="It's here">"#).title == "It's here")
    }

    @Test func onlyTheBeginningIsExamined() {
        let padding = String(repeating: " ", count: 600_000)
        #expect(parse(padding + #"<meta property="og:title" content="Muộn">"#).title == nil)
    }
}

@Suite struct LinkMetadataImageTests {
    @Test func ogImageIsResolvedAgainstBase() {
        #expect(parse(#"<meta property="og:image" content="/img/a.png">"#).imageURL?.absoluteString
            == "https://example.com/img/a.png")
        #expect(parse(#"<meta property="og:image" content="b.png">"#).imageURL?.absoluteString
            == "https://example.com/tin/b.png")
        #expect(parse(#"<meta property="og:image" content="https://cdn.example.org/c.png">"#).imageURL?.absoluteString
            == "https://cdn.example.org/c.png")
        #expect(parse(#"<meta property="og:image" content="//cdn.example.com/d.png">"#).imageURL?.absoluteString
            == "https://cdn.example.com/d.png")
    }

    @Test func twitterImageIsSecondChoice() {
        #expect(parse(#"<meta name="twitter:image" content="/t.png">"#).imageURL?.absoluteString
            == "https://example.com/t.png")
        let both = #"<meta name="twitter:image" content="/t.png"><meta property="og:image" content="/o.png">"#
        #expect(parse(both).imageURL?.absoluteString == "https://example.com/o.png")
    }

    @Test(arguments: ["javascript:alert(1)", "data:image/png;base64,AAAA", "file:///etc/passwd", "", "   "])
    func dangerousOrEmptyImageValuesAreRejected(_ value: String) {
        #expect(parse("<meta property=\"og:image\" content=\"\(value)\">").imageURL == nil)
    }

    @Test func entityInImageURLIsDecoded() {
        #expect(parse(#"<meta property="og:image" content="/i.png?a=1&amp;b=2">"#).imageURL?.absoluteString
            == "https://example.com/i.png?a=1&b=2")
    }
}
