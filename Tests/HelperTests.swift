import Foundation

@main
struct HelperTests {
    static func main() throws {
        for invalid in [-2, 1, 14, 481, Int.max, Int.min] {
            do { _ = try HelperIdentity.command(minutes: invalid); fatalError("Unexpected sleep command accepted") } catch {}
        }
        precondition(tryValue { try HelperIdentity.command(minutes: -1) } == SleepCommands.stop)
        for duration in Preferences.durations + [0] { _ = try HelperIdentity.command(minutes: duration) }
        precondition(!HelperIdentity.validHash("a\" or true"))
        precondition(!HelperIdentity.validHash(String(repeating: "z", count: 40)))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonappa-helper-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("NoNappa's app.app")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: app)
        let client = try HelperClient(bundleURL: app)
        let hash = try HelperIdentity.hash(at: app)
        precondition(HelperIdentity.validHash(hash))
        let destination = root.appendingPathComponent("installed")
        let plist = root.appendingPathComponent("helper.plist")
        let log = root.appendingPathComponent("launchctl-log")
        let launchctl = root.appendingPathComponent("launchctl")
        try "#!/bin/sh\necho \"$*\" >> \"$NONAPPA_TEST_LOG\"\n".write(to: launchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launchctl.path)
        // Keep real copy, code-signature validation, shell quoting, and plist/config serialization.
        // Substitute only root ownership and launchd system registration.
        let command = try client.installationCommand()
            .replacingOccurrences(of: HelperIdentity.directory, with: destination.path)
            .replacingOccurrences(of: HelperIdentity.launchPlist, with: plist.path)
            .replacingOccurrences(of: "/usr/bin/install -o root -g wheel", with: "/usr/bin/install")
            .replacingOccurrences(of: "/usr/sbin/chown root:wheel", with: "/usr/bin/true")
            .replacingOccurrences(of: "/bin/launchctl", with: quote(launchctl.path))
        precondition(tryValue { try run(command, log: log.path) } == 0)
        let config = try JSONDecoder().decode(HelperIdentity.self, from: Data(contentsOf: destination.appendingPathComponent("identity.json")))
        precondition(config.appHash == hash && config.userID == getuid())
        let installedHash = try HelperIdentity.hash(at: destination.appendingPathComponent("NoNappaHelper"))
        precondition(config.helperHash == installedHash)
        let job = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        precondition((job["MachServices"] as? [String: Bool])?[HelperIdentity.service] == true)

        // A modified executable must fail verification before replacing the existing helper.
        let beforeLog = try Data(contentsOf: log)
        let beforeHelper = try Data(contentsOf: destination.appendingPathComponent("NoNappaHelper"))
        try Data("not signed code".utf8).write(to: app.appendingPathComponent("Contents/Helpers/NoNappaHelper"))
        precondition(tryValue { try run(command, log: log.path) } != 0)
        precondition(tryValue { try Data(contentsOf: log) } == beforeLog)
        precondition(tryValue { try Data(contentsOf: destination.appendingPathComponent("NoNappaHelper")) } == beforeHelper)
        print("Passed: helper command allowlist, signature hashing, installer quoting, signed helper installation, user/build pinning, tampered helper rejection before service replacement.")
    }

    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func tryValue<T>(_ action: () throws -> T) -> T { try! action() }
    private static func run(_ command: String, log: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "NONAPPA_TEST_LOG": log]
        try process.run(); process.waitUntilExit()
        return process.terminationStatus
    }
}
