import Foundation
import CryptoKit

// File-based Sparkle seed generation; never touches the login Keychain.
let args = CommandLine.arguments
guard args.count == 4, ["generate", "verify"].contains(args[1]) else {
    fatalError("Usage: swift scripts/update-key.swift generate|verify PRIVATE_FILE PUBLIC_FILE")
}
let privateURL = URL(fileURLWithPath: args[2])
let publicURL = URL(fileURLWithPath: args[3])
if args[1] == "generate" {
    guard !FileManager.default.fileExists(atPath: privateURL.path), !FileManager.default.fileExists(atPath: publicURL.path) else {
        fatalError("Refusing to overwrite an update signing key")
    }
    let key = Curve25519.Signing.PrivateKey()
    guard FileManager.default.createFile(atPath: privateURL.path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600]) else { fatalError("Cannot save private seed") }
    try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to: publicURL)
} else {
    let encoded = try String(contentsOf: privateURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let expected = try String(contentsOf: publicURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: encoded), seed.count == 32 else { fatalError("Invalid update seed") }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    guard key.publicKey.rawRepresentation.base64EncodedString() == expected else { fatalError("Update public/private keys do not match") }
}
