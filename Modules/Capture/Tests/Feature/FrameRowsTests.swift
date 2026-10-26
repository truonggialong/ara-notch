import CaptureCore
import CoreGraphics
import Testing
@testable import CaptureFeature

@Suite struct FrameRowsTests {
    private static let width = 200

    /// A tall "page" of grey blocks, different in every row, so each row is recognisable by
    /// how bright it is from left to right, as a row of text is.
    private func makePage(height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: Self.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let blockWidth = 10
        for row in 0..<height {
            for block in 0..<(Self.width / blockWidth) {
                let grey = CGFloat((row &* 7919 &+ block &* 104_729 &+ row &* block &* 31) % 256) / 255
                context.setFillColor(CGColor(red: grey, green: grey, blue: grey, alpha: 1))
                // Row 0 is the top of the page; the context's origin is at the bottom.
                context.fill(CGRect(x: block * blockWidth, y: height - 1 - row, width: blockWidth, height: 1))
            }
        }
        return try #require(context.makeImage())
    }

    /// What is on screen when the page is scrolled down by `offset` rows.
    private func frame(of page: CGImage, at offset: Int, height: Int) throws -> CGImage {
        try #require(page.cropping(to: CGRect(x: 0, y: offset, width: Self.width, height: height)))
    }

    @Test func rowsOfTheSameContentGetTheSameNumber() throws {
        let page = try makePage(height: 600)
        let first = FrameRows.signatures(of: try frame(of: page, at: 0, height: 300))
        let second = FrameRows.signatures(of: try frame(of: page, at: 120, height: 300))
        #expect(first.count == 300)
        #expect(Array(first[120...]) == Array(second[..<180]))
        #expect(ScrollStitcher.shift(from: first, to: second) == 120)
    }

    @Test func joiningScrolledFramesGivesThePageBack() throws {
        let page = try makePage(height: 1000)
        var stitcher = ScrollStitcher()
        var parts: [(image: CGImage, rows: Int)] = []
        // The last frame repeats: the page has reached its end.
        for offset in [0, 250, 500, 700, 700] {
            let image = try frame(of: page, at: offset, height: 300)
            switch stitcher.add(FrameRows.signatures(of: image)) {
            case .first: parts.append((image, image.height))
            case .appended(let newRows): parts.append((image, newRows))
            case .noMovement, .movedBack, .lost: break
            }
        }
        let joined = try #require(FrameRows.stitch(parts))
        #expect(joined.height == 1000)
        #expect(FrameRows.signatures(of: joined) == FrameRows.signatures(of: page))
    }
}

@Suite @MainActor struct ScrollStepTests {
    @Test func aStepThatMovedTooLittleGrows() {
        // 2 lines moved the page 40 of 800 rows; half a frame needs ten times that.
        #expect(ScrollCaptureSession.adjustedLines(2, moved: 40, frameHeight: 800) == 20)
    }

    @Test func aStepThatMovedTooMuchShrinks() {
        #expect(ScrollCaptureSession.adjustedLines(20, moved: 700, frameHeight: 800) == 11)
    }

    @Test func theStepStaysWithinBounds() {
        #expect(ScrollCaptureSession.adjustedLines(30, moved: 10, frameHeight: 800) == 40)
        #expect(ScrollCaptureSession.adjustedLines(1, moved: 790, frameHeight: 800) == 1)
        #expect(ScrollCaptureSession.adjustedLines(5, moved: 0, frameHeight: 800) == 5)
    }
}

