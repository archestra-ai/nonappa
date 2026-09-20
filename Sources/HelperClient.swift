import Foundation

final class HelperClient {
    private let bundledHelper: URL
    private let identity: HelperIdentity

    init(bundleURL: URL = Bundle.main.bundleURL) throws {
        bundledHelper = bundleURL.appendingPathComponent("Contents/Helpers/NoNappaHelper")
        identity = HelperIdentity(userID: getuid(), appHash: try HelperIdentity.hash(at: bundleURL),
                                  helperHash: try HelperIdentity.hash(at: bundledHelper))
    }

    var installed: Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: HelperIdentity.configuration)),
              let saved = try? JSONDecoder().decode(HelperIdentity.self, from: data) else { return false }
        return saved.userID == identity.userID && saved.appHash == identity.appHash && saved.helperHash == identity.helperHash
    }

    func change(minutes: Int) async throws {
        _ = try HelperIdentity.command(minutes: minutes)
        try await request(minutes: minutes)
    }

    func ping() async throws { try await request(minutes: nil) }

    func installationCommand() throws -> String {
        let config = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "Label": HelperIdentity.service,
            "ProgramArguments": [HelperIdentity.executable],
            "MachServices": [HelperIdentity.service: true],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 5,
        ], format: .xml, options: 0)
        return """
        set -e
        /bin/mkdir -p \(HelperIdentity.directory)
        /usr/sbin/chown root:wheel \(HelperIdentity.directory)
        /bin/chmod 755 \(HelperIdentity.directory)
        /usr/bin/install -o root -g wheel -m 755 \(quote(bundledHelper.path)) \(HelperIdentity.executable).new
        /usr/bin/codesign --verify --strict -R \(quote("=cdhash H\"\(identity.helperHash)\"")) \(HelperIdentity.executable).new
        /bin/launchctl bootout system/\(HelperIdentity.service) >/dev/null 2>&1 || true
        /bin/mv -f \(HelperIdentity.executable).new \(HelperIdentity.executable)
        /bin/rm -f \(HelperIdentity.configuration) \(HelperIdentity.launchPlist)
        umask 022
        printf '%s' \(quote(config)) > \(HelperIdentity.configuration)
        printf '%s' \(quote(String(decoding: plist, as: UTF8.self))) > \(HelperIdentity.launchPlist)
        /usr/sbin/chown root:wheel \(HelperIdentity.configuration) \(HelperIdentity.launchPlist)
        /bin/chmod 644 \(HelperIdentity.configuration) \(HelperIdentity.launchPlist)
        /bin/launchctl bootstrap system \(HelperIdentity.launchPlist)
        """
    }

    private func request(minutes: Int?) async throws {
        let connection = NSXPCConnection(machServiceName: HelperIdentity.service, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.setCodeSigningRequirement("cdhash H\"\(identity.helperHash)\"")
        defer { connection.invalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = ReplyOnce(continuation)
            connection.invalidationHandler = { completion.finish(AppError.message("Helper disconnected. Use Enable one-click controls to install or repair it.")) }
            connection.interruptionHandler = { completion.finish(AppError.message("Helper interrupted. Try again.")) }
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { completion.finish($0) } as! SleepHelperProtocol
            if let minutes {
                proxy.setSleep(minutes: minutes) { error in completion.finish(error.map { AppError.message($0) }) }
            } else {
                proxy.ping { version in
                    completion.finish(version == "NoNappaHelper-1" ? nil : AppError.message("Unexpected helper version."))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                completion.finish(AppError.message("Helper timed out. Refresh status before trying again."))
            }
        }
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }

    func finish(_ error: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }
}
