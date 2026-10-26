import Testing
@testable import CaptureCore

/// A "page" is a run of numbered rows; a frame is the window of it that is on screen.
private func frame(from start: Int, height: Int = 100) -> [RowSignature] {
    (start..<(start + height)).map { RowSignature(UInt64($0) &* 2_654_435_761) }
}

@Suite struct ScrollOverlapTests {
    @Test func findsHowFarThePageMoved() {
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: frame(from: 40)) == 40)
        #expect(ScrollStitcher.shift(from: frame(from: 500), to: frame(from: 501)) == 1)
    }

    @Test func noMovementIsAShiftOfZero() {
        #expect(ScrollStitcher.shift(from: frame(from: 7), to: frame(from: 7)) == 0)
    }

    @Test func framesWithNothingInCommonHaveNoShift() {
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: frame(from: 5000)) == nil)
    }

    @Test func tooLittleOverlapIsNotTrusted() {
        // Only 5 of 100 rows still on screen: below the minimum overlap.
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: frame(from: 95)) == nil)
    }

    @Test func aFewChangedRowsAreTolerated() {
        // A blinking caret or a fading scroll bar changes a row or two between frames.
        var next = frame(from: 30)
        next[10] = 1
        next[55] = 2
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: next) == 30)
    }

    @Test func framesOfDifferentHeightsAreNotCompared() {
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: frame(from: 10, height: 90)) == nil)
    }
}

@Suite struct ScrollStitcherTests {
    @Test func theFirstFrameIsTakenWhole() {
        var stitcher = ScrollStitcher()
        let result1 = stitcher.add(frame(from: 0))
        #expect(result1 == .first)
        #expect(stitcher.totalRows == 100)
    }

    @Test func laterFramesAddOnlyTheirNewRows() {
        var stitcher = ScrollStitcher()
        _ = stitcher.add(frame(from: 0))
        let result2 = stitcher.add(frame(from: 60))
        #expect(result2 == .appended(newRows: 60))
        let result3 = stitcher.add(frame(from: 90))
        #expect(result3 == .appended(newRows: 30))
        #expect(stitcher.totalRows == 190)
    }

    @Test func aFrameThatDidNotMoveAddsNothing() {
        var stitcher = ScrollStitcher()
        _ = stitcher.add(frame(from: 0))
        let result4 = stitcher.add(frame(from: 0))
        #expect(result4 == .noMovement)
        #expect(stitcher.totalRows == 100)
    }

    @Test func aFrameThatCannotBePlacedIsLost() {
        var stitcher = ScrollStitcher()
        _ = stitcher.add(frame(from: 0))
        let result5 = stitcher.add(frame(from: 9000))
        #expect(result5 == .lost)
        #expect(stitcher.totalRows == 100)
    }

    @Test func stopsWhenThePictureWouldGrowTooTall() {
        var stitcher = ScrollStitcher(maximumRows: 150)
        _ = stitcher.add(frame(from: 0))
        let result6 = stitcher.add(frame(from: 40))
        #expect(result6 == .appended(newRows: 40))
        #expect(stitcher.isFull == false)
        let result7 = stitcher.add(frame(from: 80))
        #expect(result7 == .appended(newRows: 10))
        #expect(stitcher.totalRows == 150)
        #expect(stitcher.isFull)
    }
}

@Suite struct ScrollDirectionTests {
    @Test func aFrameFromFurtherUpThePageIsReportedAsMovedBack() {
        var stitcher = ScrollStitcher()
        _ = stitcher.add(frame(from: 200))
        let result = stitcher.add(frame(from: 150))
        #expect(result == .movedBack)
        #expect(stitcher.totalRows == 100)
    }

    @Test func afterMovingBackThePageIsPickedUpWhereItWas() {
        var stitcher = ScrollStitcher()
        _ = stitcher.add(frame(from: 200))
        _ = stitcher.add(frame(from: 150))
        // Scrolling the other way passes the old position and goes on.
        let again = stitcher.add(frame(from: 200))
        #expect(again == .noMovement)
        let onward = stitcher.add(frame(from: 250))
        #expect(onward == .appended(newRows: 50))
        #expect(stitcher.totalRows == 150)
    }
}

@Suite struct ScrollMatchQualityTests {
    @Test func rowsThatAreDrawnLateDoNotBreakTheMatch() {
        // Spelling underlines appear a moment after a scroll: one row in ten differs.
        var next = frame(from: 30)
        for index in stride(from: 3, to: 100, by: 10) {
            next[index] = RowSignature(UInt64(index))
        }
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: next) == 30)
    }

    @Test func theBestMatchingShiftWinsNotTheFirstPassableOne() {
        // A page of repeating bands: a shift of one band matches too, but worse than the true one.
        let band: [RowSignature] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        var previous = (0..<10).flatMap { _ in band }
        var next = previous
        // The true movement is two bands; mark rows so that only that shift lines everything up.
        previous[25] = 777
        next[5] = 777
        previous[60] = 888
        next[40] = 888
        #expect(ScrollStitcher.shift(from: previous, to: next) == 20)
    }

    @Test func halfTheRowsDifferingIsNoMatch() {
        var next = frame(from: 30)
        for index in stride(from: 0, to: 100, by: 2) {
            next[index] = RowSignature(UInt64(index))
        }
        #expect(ScrollStitcher.shift(from: frame(from: 0), to: next) == nil)
    }
}

@Suite struct RowSignatureTests {
    private let row = RowSignature(bands: [1, 2, 3, 4, 5, 6, 7, 8])

    @Test func aRowThatChangedInOneNarrowPlaceStillMatches() {
        // A caret, a spelling underline: one or two of the eight column bands differ.
        #expect(row.matches(RowSignature(bands: [1, 2, 99, 4, 5, 6, 7, 8])))
        #expect(row.matches(RowSignature(bands: [1, 2, 99, 98, 5, 6, 7, 8])))
    }

    @Test func aRowThatChangedInManyPlacesDoesNot() {
        #expect(!row.matches(RowSignature(bands: [1, 2, 99, 98, 97, 6, 7, 8])))
    }

    @Test func aBandMayBeALittleBrighterOrDarker() {
        // The same content is not drawn to the very same pixel values after a scroll.
        #expect(RowSignature(100).matches(RowSignature(104)))
        #expect(!RowSignature(100).matches(RowSignature(120)))
    }

    @Test func distanceAddsUpTheBandDifferences() {
        #expect(row.distance(to: RowSignature(bands: [1, 2, 3, 4, 5, 6, 7, 8])) == 0)
        #expect(row.distance(to: RowSignature(bands: [3, 2, 3, 4, 5, 6, 7, 5])) == 5)
        #expect(row.distance(to: RowSignature(bands: [1, 2])) == nil)
    }

    @Test func rowsWithDifferentBandCountsNeverMatch() {
        #expect(!row.matches(RowSignature(bands: [1, 2, 3, 4])))
    }
}

@Suite struct RepeatingPageTests {
    /// A list whose lines look alike except for their number: seven bands repeat every ten
    /// rows, and only the first band (where the number is) tells one line from the next.
    private func listFrame(from start: Int, height: Int = 100) -> [RowSignature] {
        (start..<(start + height)).map { row in
            RowSignature(bands: [UInt64(1000 + row / 10)] + (1...7).map { UInt64(row % 10 * 10 + $0) })
        }
    }

    @Test func aListOfLookAlikeLinesIsPlacedByItsNumbers() {
        #expect(ScrollStitcher.shift(from: listFrame(from: 0), to: listFrame(from: 30)) == 30)
        #expect(ScrollStitcher.shift(from: listFrame(from: 200), to: listFrame(from: 250)) == 50)
    }

    @Test func aListThatDidNotMoveIsStillNoMovement() {
        #expect(ScrollStitcher.shift(from: listFrame(from: 40), to: listFrame(from: 40)) == 0)
    }
}

