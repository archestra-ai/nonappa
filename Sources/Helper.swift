import Foundation

@main
struct HelperMain {
    static func main() throws {
        guard geteuid() == 0 else { throw AppError.message("The helper must be launched by the system.") }
        let identity = try JSONDecoder().decode(HelperIdentity.self, from: Data(contentsOf: URL(fileURLWithPath: HelperIdentity.configuration)))
        guard HelperIdentity.validHash(identity.appHash), identity.userID > 0 else {
            throw AppError.message("Invalid helper identity.")
        }
        let delegate = HelperService(identity: identity)
        let listener = NSXPCListener(machServiceName: HelperIdentity.service)
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { RunLoop.current.run() }
    }
}

final class HelperService: NSObject, NSXPCListenerDelegate, SleepHelperProtocol {
    private let identity: HelperIdentity
    private let queue = DispatchQueue(label: "com.nonappa.sleep-commands")

    init(identity: HelperIdentity) { self.identity = identity }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == identity.userID else { return false }
        // XPC enforces the peer signature on messages, avoiding PID-based verification races.
        connection.setCodeSigningRequirement("cdhash H\"\(identity.appHash)\"")
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func ping(reply: @escaping (String) -> Void) { reply("NoNappaHelper-1") }

    func setSleep(minutes: Int, reply: @escaping (String?) -> Void) {
        queue.async {
            do {
                let command = try HelperIdentity.command(minutes: minutes)
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                // Never inherit executable search paths or shell startup hooks from a client.
                process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/root"]
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw AppError.message("Sleep change failed: " + String(decoding: data, as: UTF8.self))
                }
                reply(nil)
            } catch { reply(error.localizedDescription) }
        }
    }
}
