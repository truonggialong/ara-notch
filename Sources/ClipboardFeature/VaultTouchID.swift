import Foundation
import LocalAuthentication
import Security

/// Where the passcode of the locked boards is kept for the fingerprint: one item in the
/// user's login keychain, per data folder. It is written only while the user has turned
/// unlocking by fingerprint on, and removed when they turn it off.
struct VaultKeychain {
    private static let service = "com.aranotch.app.vault"
    let account: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    var hasPasscode: Bool {
        SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func save(_ passcode: String) {
        let data = Data(passcode.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The fingerprint reader, asked whether the person at the Mac is its owner.
enum VaultFingerprint {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// The system answers on a queue of its own; the answer is carried to the main actor.
    nonisolated static func ask(reason: String, completion: @escaping @MainActor (Bool) -> Void) {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { isOwner, _ in
            Task { @MainActor in completion(isOwner) }
        }
    }
}
