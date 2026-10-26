import Foundation
import Testing
@testable import NotchCore

@Suite struct TooltipPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func sitsCentredJustBelowItsButton() {
        let anchor = CGRect(x: 700, y: 900, width: 28, height: 28)
        let origin = TooltipPlacement.origin(anchor: anchor, size: CGSize(width: 80, height: 22), screen: screen)
        #expect(origin == CGPoint(x: 674, y: 900 - 6 - 22))
    }

    @Test func goesAboveWhenThereIsNoRoomBelow() {
        let anchor = CGRect(x: 700, y: 10, width: 28, height: 28)
        let origin = TooltipPlacement.origin(anchor: anchor, size: CGSize(width: 80, height: 22), screen: screen)
        // Above the button: its top edge at 38, plus the gap.
        #expect(origin.y == CGFloat(44))
    }

    @Test func staysInsideTheScreenSideways() {
        let size = CGSize(width: 120, height: 22)
        let left = TooltipPlacement.origin(anchor: CGRect(x: 2, y: 500, width: 20, height: 20), size: size, screen: screen)
        let right = TooltipPlacement.origin(anchor: CGRect(x: 1500, y: 500, width: 10, height: 20), size: size, screen: screen)
        #expect(left.x == 4)
        #expect(right.x == CGFloat(1388))
    }
}

@Suite struct NotchKeyTests {
    @Test func namesTheKeysTheOpenNotchAnswersTo() {
        #expect(NotchKey(keyCode: 123, isShiftDown: false) == .left)
        #expect(NotchKey(keyCode: 124, isShiftDown: false) == .right)
        #expect(NotchKey(keyCode: 126, isShiftDown: false) == .up)
        #expect(NotchKey(keyCode: 125, isShiftDown: false) == .down)
        #expect(NotchKey(keyCode: 36, isShiftDown: false) == .confirm)
        #expect(NotchKey(keyCode: 49, isShiftDown: false) == .space)
        #expect(NotchKey(keyCode: 51, isShiftDown: false) == .delete)
        #expect(NotchKey(keyCode: 53, isShiftDown: false) == .escape)
    }

    @Test func tabGoesToTheNextPageAndShiftTabBack() {
        #expect(NotchKey(keyCode: 48, isShiftDown: false) == .nextPage)
        #expect(NotchKey(keyCode: 48, isShiftDown: true) == .previousPage)
    }

    @Test func otherKeysAreNotTheNotchsBusiness() {
        #expect(NotchKey(keyCode: 0, isShiftDown: false) == nil)
    }

    @Test func whileTextIsBeingTypedOnlyLeavingKeysAreTaken() {
        #expect(NotchKey.escape.worksWhileTyping)
        #expect(NotchKey.nextPage.worksWhileTyping)
        #expect(!NotchKey.left.worksWhileTyping)
        #expect(!NotchKey.space.worksWhileTyping)
        #expect(!NotchKey.delete.worksWhileTyping)
        #expect(!NotchKey.confirm.worksWhileTyping)
    }
}
