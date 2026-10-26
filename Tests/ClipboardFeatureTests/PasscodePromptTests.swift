import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct PasscodePromptTests {
    @Test func aRefusedPasscodeIsClearedSoTheNextTryStartsEmpty() {
        var prompt = ClipboardViewModel.PasscodePrompt(purpose: .view(boardID: 1))
        prompt.passcode = "9999"
        prompt.refuse(because: "clipboard.vault.error.wrong")
        #expect(prompt.passcode.isEmpty)
        #expect(prompt.errorKey == "clipboard.vault.error.wrong")
    }

    @Test func aMismatchClearsBothEntries() {
        var prompt = ClipboardViewModel.PasscodePrompt(purpose: .createAndLock(boardID: 1))
        prompt.passcode = "1234"
        prompt.confirmation = "1243"
        prompt.refuse(because: "clipboard.vault.error.mismatch")
        #expect(prompt.passcode.isEmpty)
        #expect(prompt.confirmation.isEmpty)
    }
}
