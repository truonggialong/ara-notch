import CommonCrypto
import CryptoKit
import Foundation

/// The random data key that encrypts vault content. Lives in memory only while the vault is unlocked.
struct VaultKey: Equatable {
    let data: Data

    fileprivate var symmetric: SymmetricKey { SymmetricKey(data: data) }
}

/// What is stored on disk about the vault: enough to check a passcode and recover the data
/// key with it, and nothing that reveals either.
struct VaultRecord: Equatable {
    let salt: Data
    let iterations: Int
    /// The data key, sealed with a key derived from the passcode.
    let wrappedKey: Data
}

/// Key derivation and encryption for locked boards.
///
/// Content is encrypted with a random data key (AES-256-GCM). The data key is wrapped with a
/// key derived from the passcode (PBKDF2-HMAC-SHA256), so changing the passcode re-wraps one
/// small key instead of re-encrypting everything.
enum VaultCrypto {
    static let iterations = 600_000
    static let saltLength = 16
    static let keyLength = 32

    static func makeVault(passcode: String) throws -> (record: VaultRecord, key: VaultKey) {
        let key = VaultKey(data: randomBytes(keyLength))
        return (try wrap(key, passcode: passcode), key)
    }

    /// Recovers the data key. A wrong passcode fails the authenticated unwrap.
    static func unlock(_ record: VaultRecord, passcode: String) throws -> VaultKey {
        let wrappingKey = try derive(passcode: passcode, salt: record.salt, iterations: record.iterations)
        guard let box = try? AES.GCM.SealedBox(combined: record.wrappedKey),
              let data = try? AES.GCM.open(box, using: wrappingKey), data.count == keyLength
        else { throw ClipboardStoreError.wrongPasscode }
        return VaultKey(data: data)
    }

    /// Same data key under a new passcode, with a fresh salt.
    static func rewrap(_ record: VaultRecord, from old: String, to new: String) throws -> VaultRecord {
        try wrap(try unlock(record, passcode: old), passcode: new)
    }

    static func seal(_ data: Data, with key: VaultKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key.symmetric).combined else {
            throw ClipboardStoreError.sqlite("cannot seal data")
        }
        return combined
    }

    /// Throws when the data was not sealed with this key or has been altered.
    static func open(_ data: Data, with key: VaultKey) throws -> Data {
        try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key.symmetric)
    }

    /// A keyed digest (HMAC-SHA256, hex). Used for names and content hashes of vault items, so
    /// they cannot be matched against the hashes of ordinary content without the key.
    static func keyedHash(_ value: String, with key: VaultKey) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key.symmetric)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Private

    private static func wrap(_ key: VaultKey, passcode: String) throws -> VaultRecord {
        let salt = randomBytes(saltLength)
        let wrappingKey = try derive(passcode: passcode, salt: salt, iterations: iterations)
        guard let wrapped = try AES.GCM.seal(key.data, using: wrappingKey).combined else {
            throw ClipboardStoreError.sqlite("cannot wrap key")
        }
        return VaultRecord(salt: salt, iterations: iterations, wrappedKey: wrapped)
    }

    private static func derive(passcode: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var derived = Data(count: keyLength)
        let passcodeBytes = Array(passcode.utf8)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passcodeBytes.withUnsafeBufferPointer { passcodeBuffer in
                    passcodeBuffer.withMemoryRebound(to: CChar.self) { passcodeChars in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            passcodeChars.baseAddress, passcodeChars.count,
                            saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                            derivedBytes.bindMemory(to: UInt8.self).baseAddress, keyLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ClipboardStoreError.sqlite("key derivation failed") }
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
