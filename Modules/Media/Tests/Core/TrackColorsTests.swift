import Testing
@testable import MediaCore

private typealias RGB = TrackColors.RGB

private func pixels(_ color: RGB, count: Int) -> [RGB] { Array(repeating: color, count: count) }

@Suite struct TrackColorsTests {
    @Test func greyArtworkHasNoColour() {
        let grey = pixels(RGB(red: 0.5, green: 0.5, blue: 0.5), count: 50)
            + pixels(RGB(red: 0, green: 0, blue: 0), count: 50)
            + pixels(RGB(red: 1, green: 1, blue: 1), count: 50)
        #expect(TrackColors.from(pixels: grey) == nil)
        #expect(TrackColors.from(pixels: []) == nil)
    }

    @Test func theStrongestColourComesFirst() throws {
        let art = pixels(RGB(red: 0.9, green: 0.1, blue: 0.1), count: 70)
            + pixels(RGB(red: 0.1, green: 0.2, blue: 0.9), count: 30)
        let colors = try #require(TrackColors.from(pixels: art))
        #expect(colors.first.hue < 10 || colors.first.hue > 350)
        #expect(abs(colors.second.hue - 230) < 15)
    }

    @Test func aSingleColourGetsANeighbourForTheSecond() throws {
        let colors = try #require(TrackColors.from(pixels: pixels(RGB(red: 0.9, green: 0.1, blue: 0.1), count: 100)))
        #expect(colors.first.hue < 10 || colors.first.hue > 350)
        #expect(abs(colors.second.hue - TrackColors.neighbourTurn) < 10)
    }

    @Test func aSmallSpotOfColourIsNotTakenAsSecond() throws {
        let art = pixels(RGB(red: 0.9, green: 0.1, blue: 0.1), count: 95)
            + pixels(RGB(red: 0.1, green: 0.8, blue: 0.2), count: 5)
        let colors = try #require(TrackColors.from(pixels: art))
        #expect(abs(colors.second.hue - TrackColors.neighbourTurn) < 10)
    }

    @Test func darkColoursAreBrightenedToReadOnBlack() throws {
        let colors = try #require(TrackColors.from(pixels: pixels(RGB(red: 0.3, green: 0.05, blue: 0.05), count: 100)))
        #expect(colors.first.brightness >= TrackColors.leastBrightness - 0.001)
        #expect(colors.second.brightness >= TrackColors.leastBrightness - 0.001)
    }

    @Test func aColourAmongMostlyGreyStillCounts() throws {
        let art = pixels(RGB(red: 0.5, green: 0.5, blue: 0.5), count: 80)
            + pixels(RGB(red: 0.1, green: 0.7, blue: 0.3), count: 20)
        let colors = try #require(TrackColors.from(pixels: art))
        #expect(abs(colors.first.hue - 140) < 15)
    }
}
