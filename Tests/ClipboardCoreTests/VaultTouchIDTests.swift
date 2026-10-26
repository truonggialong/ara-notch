import Foundation
import Testing
@testable import ClipboardCore

@Suite struct VaultTouchIDTests {
    @Test func aFingerprintIsOfferedOnlyWhenEverythingItNeedsIsThere() {
        #expect(VaultTouchID.shouldOffer(isEnabled: true, hasSavedPasscode: true, canUseBiometrics: true, isCreating: false))
        #expect(!VaultTouchID.shouldOffer(isEnabled: false, hasSavedPasscode: true, canUseBiometrics: true, isCreating: false))
        #expect(!VaultTouchID.shouldOffer(isEnabled: true, hasSavedPasscode: false, canUseBiometrics: true, isCreating: false))
        #expect(!VaultTouchID.shouldOffer(isEnabled: true, hasSavedPasscode: true, canUseBiometrics: false, isCreating: false))
        // A passcode being chosen for the first time has nothing saved to stand in for it.
        #expect(!VaultTouchID.shouldOffer(isEnabled: true, hasSavedPasscode: true, canUseBiometrics: true, isCreating: true))
    }

    @Test func unlockingByFingerprintIsOffUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.vaultTouchID == false)
        store.vaultTouchID = true
        #expect(ClipboardSettingsStore(defaults: defaults).vaultTouchID == true)
    }
}
