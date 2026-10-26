import CoreGraphics
import Testing
@testable import CaptureCore

@Suite struct AnnotationMoreToolsTests {
    private let from = CGPoint(x: 10, y: 20), to = CGPoint(x: 110, y: 80)
    private let box = CGRect(x: 10, y: 20, width: 100, height: 60)

    private func shape(_ tool: AnnotationTool, from: CGPoint? = nil, to: CGPoint? = nil, step: Int = 1) -> Annotation.Shape? {
        AnnotationDocument.shape(
            for: tool, from: from ?? self.from, to: to ?? self.to, path: [], text: "", step: step)
    }

    @Test func anEllipseALineAndABlurAreDraggedOut() {
        #expect(shape(.ellipse) == .ellipse(box))
        #expect(shape(.line) == .line(from: from, to: to))
        #expect(shape(.blur) == .blur(box))
    }

    @Test func aDragTooShortDrawsNoneOfThem() {
        let near = CGPoint(x: 11, y: 21)
        #expect(shape(.ellipse, to: near) == nil)
        #expect(shape(.line, to: near) == nil)
        #expect(shape(.blur, to: near) == nil)
    }

    @Test func aStepIsPlacedWithAClickAndCarriesItsNumber() {
        let point = CGPoint(x: 40, y: 40)
        #expect(shape(.step, from: point, to: point, step: 3) == .step(3, at: point))
    }

    @Test func stepsAreNumberedInTheOrderTheyArePlacedAndUndoGivesTheNumberBack() {
        var document = AnnotationDocument()
        #expect(document.nextStepNumber == 1)
        document.add(.step(1, at: .zero), color: .red, lineWidth: 4)
        document.add(.rectangle(box), color: .red, lineWidth: 4)
        #expect(document.nextStepNumber == 2)
        document.add(.step(2, at: .zero), color: .red, lineWidth: 4)
        #expect(document.nextStepNumber == 3)
        document.undo()
        #expect(document.nextStepNumber == 2)
    }

    @Test func thereAreThreeStrokeWidthsAndTheMiddleOneIsTheOldWidth() {
        #expect(AnnotationStroke.allCases == [.small, .medium, .large])
        #expect(AnnotationStroke.medium.width == 4)
        #expect(AnnotationStroke.small.width < AnnotationStroke.medium.width)
        #expect(AnnotationStroke.large.width > AnnotationStroke.medium.width)
    }

    @Test func aMosaicHasAtLeastAFewBlocksEachWay() {
        // A small box still breaks into blocks; a large one does not get blocks so small
        // that what is under it can be read.
        #expect(MosaicGeometry.blocks(for: CGSize(width: 40, height: 20)) == MosaicGeometry.Blocks(columns: 4, rows: 2))
        #expect(MosaicGeometry.blocks(for: CGSize(width: 400, height: 120)) == MosaicGeometry.Blocks(columns: 34, rows: 10))
        #expect(MosaicGeometry.blocks(for: CGSize(width: 3, height: 3)) == MosaicGeometry.Blocks(columns: 1, rows: 1))
    }
}
