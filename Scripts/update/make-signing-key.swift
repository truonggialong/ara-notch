import CryptoKit
import Foundation

// Makes the Ed25519 key that updates are signed with. Usage:
//   swift Scripts/update/make-signing-key.swift <private-key-file>
// The private key (base64 of its 32-byte seed, the form Sparkle's sign_update and
// generate_appcast read with --ed-key-file) is written to the file, readable by its owner
// only; nothing goes to the keychain. The public key is printed: it belongs in the app's
// Info.plist as SUPublicEDKey. An existing file is never overwritten: every copy of the app
// already installed trusts the key it was built with, and only that one.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-signing-key.swift <private-key-file>\n".utf8))
    exit(64)
}
let path = arguments[1]
if let existing = FileManager.default.contents(atPath: path),
   let seed = Data(base64Encoded: String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
   let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) {
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}
guard !FileManager.default.fileExists(atPath: path) else {
    FileHandle.standardError.write(Data("\(path) exists and is not a signing key; not touching it\n".utf8))
    exit(1)
}
let key = Curve25519.Signing.PrivateKey()
try FileManager.default.createDirectory(
    atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
guard FileManager.default.createFile(
    atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
    attributes: [.posixPermissions: 0o600])
else {
    FileHandle.standardError.write(Data("could not write \(path)\n".utf8))
    exit(1)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
