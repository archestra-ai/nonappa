import Foundation

@main
struct CoreTests {
    static func main() throws {
        let suite = "nonappa-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        precondition(preferences.minutes == 60)
        preferences.minutes = 120
        precondition(Preferences(defaults: UserDefaults(suiteName: suite)!).minutes == 120)
        preferences.minutes = 0
        precondition(Preferences(defaults: UserDefaults(suiteName: suite)!).minutes == 0)
        defaults.set(-5, forKey: "durationMinutes")
        precondition(preferences.minutes == 60)
        precondition(tryValue { try SleepStatus(output: "System-wide power settings:\n SleepDisabled\t\t1\n sleep 0").disabled })
        precondition(!tryValue { try SleepStatus(output: " SleepDisabled 0").disabled })
        precondition(!tryValue { try SleepStatus(output: "System-wide power settings:\nCurrently in use:\n sleep 0").disabled })
        for output in ["", "sleep 0", "unrecognized System-wide power settings:",
                       "System-wide power settings:\n SleepDisabled 2",
                       "System-wide power settings:\n SleepDisabled",
                       "System-wide power settings:\n SleepDisabled 1 extra"] {
            do { _ = try SleepStatus(output: output); fatalError("Unknown status must not appear asleep") } catch {}
        }
        do { _ = try SleepCommands.start(minutes: -1); fatalError("Invalid duration accepted") } catch {}

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nonappa-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("calls").path
        let plist = root.appendingPathComponent("restore.plist").path
        let pmset = root.appendingPathComponent("pmset").path
        let launchctl = root.appendingPathComponent("launchctl").path
        try writeExecutable("#!/bin/sh\nprintf '%s\\n' \"$*\" >> '\(log)'\n", to: pmset)
        try writeExecutable("#!/bin/sh\nexit 0\n", to: launchctl)
        func isolated(_ command: String) -> String {
            command.replacingOccurrences(of: SleepCommands.plistPath, with: plist)
                .replacingOccurrences(of: "/usr/bin/pmset", with: pmset)
                .replacingOccurrences(of: "/bin/launchctl", with: launchctl)
                .replacingOccurrences(of: "/usr/sbin/chown root:wheel", with: "/usr/bin/true")
        }
        let now = Date()
        let command = isolated(try SleepCommands.start(minutes: 15, now: now))
        precondition(tryValue { try run(command) } == 0)
        let data = try Data(contentsOf: URL(fileURLWithPath: plist))
        precondition(Int(SleepCommands.deadline(from: data)!.timeIntervalSince1970) == Int(now.timeIntervalSince1970) + 900)
        precondition(tryValue { try String(contentsOfFile: log, encoding: .utf8) } == "-a disablesleep 1\n")

        // Run the actual restoration worker with an already-expired deadline.
        precondition(tryValue { try run(isolated(SleepCommands.start(minutes: 15, now: Date(timeIntervalSince1970: 0)))) } == 0)
        let expiredData = try Data(contentsOf: URL(fileURLWithPath: plist))
        let job = try PropertyListSerialization.propertyList(from: expiredData, format: nil) as! [String: Any]
        let arguments = job["ProgramArguments"] as! [String]
        precondition(tryValue { try run(arguments[2]) } == 0)
        precondition(!FileManager.default.fileExists(atPath: plist))
        precondition(tryValue { try String(contentsOfFile: log, encoding: .utf8) }.hasSuffix("-a disablesleep 0\n"))

        // Indefinite mode cancels an existing timer and enables sleep prevention without a new deadline.
        precondition(tryValue { try run(command) } == 0)
        precondition(tryValue { try run(isolated(SleepCommands.start(minutes: 0))) } == 0)
        precondition(!FileManager.default.fileExists(atPath: plist))
        precondition(tryValue { try String(contentsOfFile: log, encoding: .utf8) }.hasSuffix("-a disablesleep 0\n-a disablesleep 1\n"))

        // If launchd cannot schedule restoration, enabling sleep prevention rolls back.
        try writeExecutable("#!/bin/sh\nexit 1\n", to: launchctl)
        precondition(tryValue { try run(command) } != 0)
        precondition(!FileManager.default.fileExists(atPath: plist))
        precondition(tryValue { try String(contentsOfFile: log, encoding: .utf8) }.hasSuffix("-a disablesleep 1\n-a disablesleep 0\n"))
        precondition(tryValue { try run(isolated(SleepCommands.stop)) } == 0)

        // Compile the real authorization script without executing or requesting privileges.
        let script = root.appendingPathComponent("authorize.applescript")
        try SleepCommands.appleScript(for: command).write(to: script, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        compiler.arguments = ["-o", root.appendingPathComponent("compiled.scpt").path, script.path]
        try compiler.run(); compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0)
        print("Passed: saved settings, status parsing, duration validation, timer persistence, independent restoration, failure rollback, stop, authorization script compilation.")
    }

    private static func tryValue<T>(_ action: () throws -> T) -> T { try! action() }

    private static func run(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run(); process.waitUntilExit()
        return process.terminationStatus
    }

    private static func writeExecutable(_ text: String, to path: String) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }
}
