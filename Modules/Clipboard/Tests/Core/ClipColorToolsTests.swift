import Foundation
import Testing
@testable import ClipboardCore

@Suite struct BareHexColorTests {
    @Test(arguments: ["4A90D9", "ff0000", " 00000080 "])
    func bareHexIsAColourOnlyWhenAllowed(_ text: String) {
        #expect(ClipColor.parse(text) == nil)
        #expect(ClipColor.parse(text, allowingBareHex: true) != nil)
        #expect(ClipClassifier.kind(of: .text(text)) == .text)
        #expect(ClipClassifier.kind(of: .text(text), allowingBareHex: true) == .color)
    }

    @Test func bareHexReadsTheSameAsWithTheHash() {
        #expect(ClipColor.parse("4A90D9", allowingBareHex: true) == ClipColor.parse("#4A90D9"))
    }

    /// Three digits are too easily a word or a number.
    @Test(arguments: ["fff", "abc", "123", "12345", "1234567", "4A90DG", "bad cafe", "decade!"])
    func otherBareStringsStayText(_ text: String) {
        #expect(ClipColor.parse(text, allowingBareHex: true) == nil)
        #expect(ClipClassifier.kind(of: .text(text), allowingBareHex: true) == .text)
    }

    @Test func theStoreClassifiesBareHexWhenToldTo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-colour-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directory: directory, inMemory: true)
        let source = ClipSource()

        let plain = try store.add(.text("4A90D9"), source: source, at: Date(timeIntervalSince1970: 1))
        #expect(plain?.kind == .text)

        store.recognisesBareHexColors = true
        let colour = try store.add(.text("FF8800"), source: source, at: Date(timeIntervalSince1970: 2))
        #expect(colour?.kind == .color)
    }
}

@Suite struct ColorFormatTests {
    private func formatted(_ source: String, _ format: ClipColor.Format) -> String? {
        ClipColor.parse(source)?.formatted(as: format)
    }

    @Test func writesHex() {
        #expect(formatted("rgb(74, 144, 217)", .hex) == "#4A90D9")
        #expect(formatted("#fff", .hex) == "#FFFFFF")
        #expect(formatted("rgba(0, 0, 0, 0.5)", .hex) == "#00000080")
    }

    @Test func writesRGB() {
        #expect(formatted("#4A90D9", .rgb) == "rgb(74, 144, 217)")
        #expect(formatted("#00000080", .rgb) == "rgba(0, 0, 0, 0.5)")
        #expect(formatted("hsl(120, 100%, 25%)", .rgb) == "rgb(0, 128, 0)")
    }

    @Test func writesHSL() {
        #expect(formatted("#4A90D9", .hsl) == "hsl(211, 65%, 57%)")
        #expect(formatted("#FF0000", .hsl) == "hsl(0, 100%, 50%)")
        #expect(formatted("#FFFFFF", .hsl) == "hsl(0, 0%, 100%)")
        #expect(formatted("#123456", .hsl) == "hsl(210, 65%, 20%)")
        #expect(formatted("rgba(255, 0, 0, 0.25)", .hsl) == "hsla(0, 100%, 50%, 0.25)")
    }

    @Test func everyFormatReadsBackAsTheSameColour() throws {
        let colour = try #require(ClipColor.parse("#4A90D9"))
        for format in ClipColor.Format.allCases {
            let again = try #require(ClipColor.parse(colour.formatted(as: format)))
            // HSL rounds to whole degrees and percent.
            #expect(abs(again.red - colour.red) < 0.02)
            #expect(abs(again.green - colour.green) < 0.02)
            #expect(abs(again.blue - colour.blue) < 0.02)
        }
    }
}
