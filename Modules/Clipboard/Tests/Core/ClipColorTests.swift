import Testing
@testable import ClipboardCore

/// Compares the four components with a small tolerance.
private func expectColor(_ string: String, _ r: Double, _ g: Double, _ b: Double, _ a: Double,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    guard let color = ClipColor.parse(string) else {
        Issue.record("\(string) did not parse", sourceLocation: sourceLocation)
        return
    }
    let actual = [color.red, color.green, color.blue, color.alpha]
    for (value, expected) in zip(actual, [r, g, b, a]) {
        #expect(abs(value - expected) < 0.001, "\(string) → \(actual)", sourceLocation: sourceLocation)
    }
}

@Suite struct ClipColorTests {
    @Test func parsesSixDigitHex() { expectColor("#4A90D9", 74 / 255, 144 / 255, 217 / 255, 1) }
    @Test func parsesThreeDigitHex() { expectColor("#fff", 1, 1, 1, 1) }
    @Test func parsesEightDigitHexWithAlpha() { expectColor("#00000080", 0, 0, 0, 128 / 255) }
    @Test func parsesRGB() { expectColor("rgb(74, 144, 217)", 74 / 255, 144 / 255, 217 / 255, 1) }
    @Test func parsesRGBAWithoutSpaces() { expectColor("rgba(255,0,0,0.5)", 1, 0, 0, 0.5) }
    @Test func parsesHSLRed() { expectColor("hsl(0, 100%, 50%)", 1, 0, 0, 1) }
    @Test func parsesHSLDarkGreen() { expectColor("hsl(120, 100%, 25%)", 0, 0.5, 0, 1) }
    @Test func parsesHSLA() { expectColor("hsla(240, 100%, 50%, 0.25)", 0, 0, 1, 0.25) }
    @Test func ignoresSurroundingWhitespace() { expectColor("  #FFF  ", 1, 1, 1, 1) }

    @Test(arguments: [
        "FF0000", "#hello", "#12345", "rgb(300, 0, 0)", "rgb(1, 2)",
        "hsl(0, 120%, 50%)", "rgba(0,0,0,2)", "", "#", "rgb()", "text #fff",
    ])
    func rejectsInvalid(_ string: String) {
        #expect(ClipColor.parse(string) == nil)
    }
}
