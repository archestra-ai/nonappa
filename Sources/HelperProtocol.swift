import Foundation
import Security

@objc protocol SleepHelperProtocol {
    func ping(reply: @escaping (String) -> Void)
    func setSleep(minutes: Int, reply: @escaping (String?) -> Void)
}

struct HelperIdentity: Codable {
    let userID: UInt32
    let appHash: String
    let helperHash: String

    static let service = "com.nonappa.helper"
    static let directory = "/Library/PrivilegedHelperTools/com.nonappa.helper"
    static let executable = directory + "/NoNappaHelper"
    static let configuration = directory + "/identity.json"
    static let launchPlist = "/Library/LaunchDaemons/com.nonappa.helper.plist"

    static func hash(at url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else {
            throw AppError.message("NoNappa’s code signature could not be verified. Rebuild the app.")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let hash = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else {
            throw AppError.message("NoNappa’s signing identity is unavailable.")
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func validHash(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func command(minutes: Int) throws -> String {
        if minutes == -1 { return SleepCommands.stop }
        return try SleepCommands.start(minutes: minutes)
    }
}
