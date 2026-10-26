import CoreGraphics
import Foundation
import Testing
@testable import CaptureCore

@Suite struct AnnotationShapeTests {
    @Test func aRectangleDragInAnyDirectionGivesAProperRectangle() {
        let shape = AnnotationDocument.shape(
            for: .rectangle, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 10), path: [], text: "")
        #expect(shape == .rectangle(CGRect(x: 10, y: 10, width: 40, height: 30)))
    }

    @Test func aHighlightIsARectangleToo() {
        let shape = AnnotationDocument.shape(
            for: .highlight, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 30, y: 12), path: [], text: "")
        #expect(shape == .highlight(CGRect(x: 0, y: 0, width: 30, height: 12)))
    }

    @Test func aTinyDragDrawsNothing() {
        let from = CGPoint(x: 10, y: 10), to = CGPoint(x: 11, y: 12)
        #expect(AnnotationDocument.shape(for: .rectangle, from: from, to: to, path: [], text: "") == nil)
        #expect(AnnotationDocument.shape(for: .arrow, from: from, to: to, path: [], text: "") == nil)
        #expect(AnnotationDocument.shape(for: .pen, from: from, to: to, path: [from], text: "") == nil)
    }

    @Test func anArrowKeepsItsDirection() {
        let shape = AnnotationDocument.shape(
            for: .arrow, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 10), path: [], text: "")
        #expect(shape == .arrow(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 10)))
    }

    @Test func thePenFollowsThePath() {
        let path = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 2)]
        #expect(AnnotationDocument.shape(for: .pen, from: path[0], to: path[2], path: path, text: "") == .pen(path))
    }

    @Test func textIsPlacedWhereTheDragEndsAndNeedsSomeText() {
        let point = CGPoint(x: 20, y: 30)
        #expect(AnnotationDocument.shape(for: .text, from: point, to: point, path: [], text: " Lỗi ở đây ")
            == .text("Lỗi ở đây", at: point))
        #expect(AnnotationDocument.shape(for: .text, from: point, to: point, path: [], text: "  ") == nil)
    }
}

@Suite struct AnnotationDocumentTests {
    private let box = Annotation.Shape.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))
    private let line = Annotation.Shape.arrow(from: .zero, to: CGPoint(x: 9, y: 9))

    @Test func addsUndoesAndRedoes() {
        var document = AnnotationDocument()
        document.add(box, color: .red, lineWidth: 3)
        document.add(line, color: .yellow, lineWidth: 3)
        #expect(document.annotations.map(\.shape) == [box, line])
        document.undo()
        #expect(document.annotations.map(\.shape) == [box])
        #expect(document.canRedo)
        document.redo()
        #expect(document.annotations.map(\.shape) == [box, line])
        #expect(!document.canRedo)
    }

    @Test func aNewShapeAfterUndoDropsWhatWasUndone() {
        var document = AnnotationDocument()
        document.add(box, color: .red, lineWidth: 3)
        document.undo()
        document.add(line, color: .red, lineWidth: 3)
        #expect(!document.canRedo)
        #expect(document.annotations.map(\.shape) == [line])
    }

    @Test func undoOnAnEmptyDocumentDoesNothing() {
        var document = AnnotationDocument()
        document.undo()
        document.redo()
        #expect(document.annotations.isEmpty)
        #expect(!document.canUndo)
    }

    @Test func theShapeBeingDrawnCanBeReplacedWhileDragging() {
        var document = AnnotationDocument()
        document.add(box, color: .red, lineWidth: 3)
        document.replaceLast(with: line)
        #expect(document.annotations.map(\.shape) == [line])
        #expect(document.annotations[0].color == .red)
    }

    @Test func everyShapeHasItsOwnID() {
        var document = AnnotationDocument()
        document.add(box, color: .red, lineWidth: 3)
        document.undo()
        document.add(box, color: .red, lineWidth: 3)
        document.add(box, color: .red, lineWidth: 3)
        #expect(Set(document.annotations.map(\.id)).count == 2)
    }
}

@Suite struct ArrowGeometryTests {
    @Test func theHeadOpensBackwardsFromTheTip() {
        let (left, right) = ArrowGeometry.head(from: .zero, to: CGPoint(x: 10, y: 0), length: 4)
        #expect(abs(left.x - 6.536) < 0.01)
        #expect(abs(right.x - 6.536) < 0.01)
        #expect(abs(abs(left.y) - 2) < 0.01)
        #expect(abs(left.y + right.y) < 0.0001)
    }
}

@Suite struct RecognizedLinesTests {
    // Vision's boxes: 0…1, origin at the bottom left.
    private func line(_ text: String, x: CGFloat, y: CGFloat) -> RecognizedLines.Line {
        RecognizedLines.Line(text: text, box: CGRect(x: x, y: y, width: 0.2, height: 0.05))
    }

    @Test func readsTopToBottom() {
        let lines = [line("dưới", x: 0.1, y: 0.2), line("trên", x: 0.1, y: 0.8), line("giữa", x: 0.1, y: 0.5)]
        #expect(RecognizedLines.text(lines) == "trên\ngiữa\ndưới")
    }

    @Test func piecesOnOneRowAreJoinedLeftToRight() {
        let lines = [line("phải", x: 0.6, y: 0.805), line("trái", x: 0.1, y: 0.8), line("dưới", x: 0.1, y: 0.5)]
        #expect(RecognizedLines.text(lines) == "trái phải\ndưới")
    }

    @Test func nothingRecognizedIsEmptyText() {
        #expect(RecognizedLines.text([]) == "")
    }
}

@Suite struct CaptureNamingTests {
    @Test func namesAFileAfterTheMoment() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 1, minute: 5, second: 9))!
        #expect(CaptureNaming.fileName(at: date, calendar: calendar) == "AraNotch 2026-10-12 01.05.09.png")
    }
}

@Suite struct CaptureSettingsStoreTests {
    @Test func theShortcutIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = CaptureSettingsStore(defaults: defaults)
        #expect(store.shortcutEnabled == false)
        store.shortcutEnabled = true
        #expect(CaptureSettingsStore(defaults: defaults).shortcutEnabled == true)
    }
}

@Suite struct ScreenColorTests {
    @Test func writesAColourAsHex() {
        #expect(ScreenColor.hex(red: 1, green: 0.5, blue: 0) == "#FF8000")
        #expect(ScreenColor.hex(red: 0, green: 0, blue: 0) == "#000000")
    }

    @Test func valuesOutsideTheRangeAreClamped() {
        // A wide-gamut display can hand back components a little outside 0…1.
        #expect(ScreenColor.hex(red: 1.02, green: -0.01, blue: 0.999) == "#FF00FF")
    }
}
