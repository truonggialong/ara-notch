import Testing
@testable import NotchCore

@Suite struct TabRowLayoutTests {
    @Test func tabsThatDoNotFitLeftOfTheNotchGoToItsRight() {
        // Nine tabs of 30 points, 2 apart, and room for 204 points beside the notch: six fit.
        #expect(TabRowLayout.leftCount(count: 9, sideWidth: 204, tabWidth: 30, spacing: 2) == 6)
    }

    @Test func tabsThatAllFitStayOnTheLeft() {
        #expect(TabRowLayout.leftCount(count: 5, sideWidth: 204, tabWidth: 30, spacing: 2) == 5)
    }

    @Test func aTabThatFitsExactlyIsNotPushedAcross() {
        // Three tabs take 30 + 2 + 30 + 2 + 30 = 94 points.
        #expect(TabRowLayout.leftCount(count: 4, sideWidth: 94, tabWidth: 30, spacing: 2) == 3)
        #expect(TabRowLayout.leftCount(count: 4, sideWidth: 93, tabWidth: 30, spacing: 2) == 2)
    }

    @Test func oneTabAlwaysStaysOnTheLeft() {
        #expect(TabRowLayout.leftCount(count: 4, sideWidth: 10, tabWidth: 30, spacing: 2) == 1)
        #expect(TabRowLayout.leftCount(count: 0, sideWidth: 204, tabWidth: 30, spacing: 2) == 0)
    }

    @Test func theRoomBesideTheNotchIsHalfOfWhatTheNotchLeaves() {
        // A row 624 points wide round a notch of 185, with 12 points kept clear at each end
        // and 6 beside the notch.
        #expect(TabRowLayout.sideWidth(rowWidth: 624, notchWidth: 185, edgePadding: 12, notchGap: 6) == 201.5)
    }
}
