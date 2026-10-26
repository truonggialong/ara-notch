import Foundation
import Testing
@testable import ClipboardCore

@Suite struct ClipClassifierTests {
    @Test func imageContentIsImage() {
        #expect(ClipClassifier.kind(of: .image(Data([1]))) == .image)
    }

    @Test func fileContentIsFile() {
        #expect(ClipClassifier.kind(of: .files(["/tmp/a.txt"])) == .file)
    }

    @Test(arguments: ["https://example.com/a?b=1", "  http://example.com\n", "HTTPS://EXAMPLE.COM"])
    func webURLIsLink(_ text: String) {
        #expect(ClipClassifier.kind(of: .text(text)) == .link)
    }

    @Test(arguments: ["#4A90D9", "rgb(74, 144, 217)", " hsl(210, 65%, 57%) "])
    func colorCodeIsColor(_ text: String) {
        #expect(ClipClassifier.kind(of: .text(text)) == .color)
    }

    @Test(arguments: [
        "hello world", "https://a.com và thêm chữ", "http://", "ftp://example.com", "example.com",
        "#hello", "rgb(300, 0, 0)", "https://a.com\nhttps://b.com",
    ])
    func everythingElseIsText(_ text: String) {
        #expect(ClipClassifier.kind(of: .text(text)) == .text)
    }
}
