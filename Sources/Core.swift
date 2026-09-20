import Foundation

struct Preferences {
    private let defaults: UserDefaults
    static let durations = [15, 30, 60, 120, 240, 480]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var minutes: Int {
        get {
            let value = defaults.integer(forKey: "durationMinutes")
            return (Self.durations.contains(value) || (value == 0 && defaults.object(forKey: "durationMinutes") != nil)) ? value : 60
        }
        nonmutating set {
            defaults.set((Self.durations.contains(newValue) || newValue == 0) ? newValue : 60, forKey: "durationMinutes")
        }
    }

    var didConfigureLogin: Bool {
        get { defaults.bool(forKey: "didConfigureLogin") }
        nonmutating set { defaults.set(newValue, forKey: "didConfigureLogin") }
    }
}

struct SleepStatus {
    let disabled: Bool

    init(output: String) throws {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.count == 2, fields[0] == "SleepDisabled", ["0", "1"].contains(fields[1]) {
                disabled = fields[1] == "1"
                return
            }
        }
        throw AppError.message("Couldn’t read the Mac’s sleep setting. Try Refresh status.")
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

// Commands are executed only after the OS grants administrator authorization.
// A root-owned launchd job restores sleep even if the UI exits or the Mac reboots.
struct SleepCommands {
    static let label = "com.nonappa.restore"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    static func start(minutes: Int, now: Date = Date()) throws -> String {
        if minutes == 0 {
            // Cancel any previous restore timer before entering indefinite mode.
            return stop + "\n/usr/bin/pmset -a disablesleep 1"
        }
        guard Preferences.durations.contains(minutes) else {
            throw AppError.message("Choose a supported timer duration.")
        }
        let deadline = Int(now.timeIntervalSince1970) + minutes * 60
        let worker = """
        while [ "$(/bin/date +%s)" -lt \(deadline) ]; do /bin/sleep 2; done
        /usr/bin/pmset -a disablesleep 0 && /bin/rm -f \(plistPath)
        """
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "Label": label,
            "ProgramArguments": ["/bin/sh", "-c", worker],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 5,
            "NoNappaDeadline": deadline,
        ], format: .xml, options: 0)
        let xml = String(decoding: data, as: UTF8.self)
        return """
        set -e
        rollback() {
            result=$?
            if [ "$result" -ne 0 ]; then
                /usr/bin/pmset -a disablesleep 0 && /bin/rm -f \(plistPath)
            fi
            exit "$result"
        }
        trap rollback EXIT
        /bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true
        /bin/rm -f \(plistPath)
        umask 022
        printf '%s' \(quote(xml)) > \(plistPath)
        /usr/sbin/chown root:wheel \(plistPath)
        /bin/chmod 644 \(plistPath)
        if /usr/bin/pmset -a disablesleep 1; then
            if /bin/launchctl bootstrap system \(plistPath); then exit 0; fi
        fi
        exit 1
        """
    }

    static var stop: String {
        """
        set -e
        /usr/bin/pmset -a disablesleep 0
        /bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true
        /bin/rm -f \(plistPath)
        """
    }

    static func deadline(from data: Data) -> Date? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let timestamp = plist["NoNappaDeadline"] as? Int else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    static func appleScript(for command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "do shell script \"\(escaped)\" with administrator privileges with prompt \"NoNappa needs permission to change sleep settings and schedule automatic sleep restoration.\""
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
