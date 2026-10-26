import Foundation
import Testing
@testable import ClipboardCore

@Suite struct VaultCryptoTests {
    @Test func createdVaultOpensWithItsPasscode() throws {
        let vault = try VaultCrypto.makeVault(passcode: "1234")
        #expect(vault.key.data.count == 32)
        #expect(vault.record.salt.count == 16)
        #expect(vault.record.iterations == 600_000)
        #expect(try VaultCrypto.unlock(vault.record, passcode: "1234") == vault.key)
    }

    @Test func wrongPasscodeIsRejected() throws {
        let vault = try VaultCrypto.makeVault(passcode: "1234")
        #expect(throws: ClipboardStoreError.wrongPasscode) {
            try VaultCrypto.unlock(vault.record, passcode: "1235")
        }
    }

    @Test func vaultsWithTheSamePasscodeDiffer() throws {
        let first = try VaultCrypto.makeVault(passcode: "1234")
        let second = try VaultCrypto.makeVault(passcode: "1234")
        #expect(first.record.salt != second.record.salt)
        #expect(first.key != second.key)
        #expect(first.record.wrappedKey != second.record.wrappedKey)
    }

    @Test func wrappedKeyDoesNotContainTheKey() throws {
        let vault = try VaultCrypto.makeVault(passcode: "1234")
        #expect(vault.record.wrappedKey.range(of: vault.key.data) == nil)
    }

    @Test(arguments: [0, 1, 37, 1_000_000])
    func sealedDataOpensBack(length: Int) throws {
        let key = try VaultCrypto.makeVault(passcode: "1234").key
        let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0) })
        let sealed = try VaultCrypto.seal(data, with: key)
        #expect(sealed != data)
        #expect(try VaultCrypto.open(sealed, with: key) == data)
    }

    @Test func sealingTwiceGivesDifferentCiphertexts() throws {
        let key = try VaultCrypto.makeVault(passcode: "1234").key
        let data = Data("bí mật".utf8)
        #expect(try VaultCrypto.seal(data, with: key) != VaultCrypto.seal(data, with: key))
    }

    @Test func tamperedDataIsRejected() throws {
        let key = try VaultCrypto.makeVault(passcode: "1234").key
        var sealed = try VaultCrypto.seal(Data("bí mật".utf8), with: key)
        sealed[sealed.count / 2] ^= 0x01
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, with: key) }
    }

    @Test func garbageIsRejected() throws {
        let key = try VaultCrypto.makeVault(passcode: "1234").key
        #expect(throws: (any Error).self) { try VaultCrypto.open(Data([1, 2, 3]), with: key) }
    }

    @Test func anotherKeyCannotOpen() throws {
        let key = try VaultCrypto.makeVault(passcode: "1234").key
        let other = try VaultCrypto.makeVault(passcode: "1234").key
        let sealed = try VaultCrypto.seal(Data("bí mật".utf8), with: key)
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, with: other) }
    }

    @Test func rewrapKeepsTheDataKey() throws {
        let vault = try VaultCrypto.makeVault(passcode: "1234")
        let rewrapped = try VaultCrypto.rewrap(vault.record, from: "1234", to: "mật mã mới")
        #expect(try VaultCrypto.unlock(rewrapped, passcode: "mật mã mới") == vault.key)
        #expect(rewrapped.salt != vault.record.salt)
        #expect(throws: ClipboardStoreError.wrongPasscode) {
            try VaultCrypto.unlock(rewrapped, passcode: "1234")
        }
    }

    @Test func rewrapNeedsTheOldPasscode() throws {
        let vault = try VaultCrypto.makeVault(passcode: "1234")
        #expect(throws: ClipboardStoreError.wrongPasscode) {
            try VaultCrypto.rewrap(vault.record, from: "sai", to: "5678")
        }
    }

    @Test func keyedHashDependsOnTheKey() throws {
        let key = try VaultCrypto.makeVault(passcode: "1234").key
        let other = try VaultCrypto.makeVault(passcode: "1234").key
        let hash = VaultCrypto.keyedHash("abc", with: key)
        #expect(hash == VaultCrypto.keyedHash("abc", with: key))
        #expect(hash != VaultCrypto.keyedHash("abd", with: key))
        #expect(hash != VaultCrypto.keyedHash("abc", with: other))
        #expect(hash.count == 64)
    }
}
