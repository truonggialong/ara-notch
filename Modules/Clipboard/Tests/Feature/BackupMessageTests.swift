import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct BackupMessageTests {
    @Test func anExportWithLockedBoardsSaysTheyAreNotInIt() {
        let message = BackupPanels.exportMessage(lockedBoardsLeftOut: 2)
        #expect(message != BackupPanels.exportMessage(lockedBoardsLeftOut: 0))
    }
}
