import AppKit
import SwiftUI
import ServiceManagement

@main
struct NoNappaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let model = SleepModel()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.image = Mascot.image(size: NSSize(width: 22, height: 20))
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("NoNappa sleep controls")
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 470)
        popover.contentViewController = NSHostingController(rootView: Panel(model: model))
        model.onChange = { [weak self] in self?.updateStatus() }
        model.refresh()
        model.configureFirstLaunch()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        updateStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        model.refresh()
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateStatus() {
        item.button?.title = ""
        item.button?.toolTip = "NoNappa — \(model.statusTitle)"
    }
}

@MainActor
final class SleepModel: ObservableObject {
    @Published var disabled: Bool?
    @Published var deadline: Date?
    @Published var busy = false
    @Published var error: String?
    @Published var minutes = Preferences().minutes {
        didSet { Preferences().minutes = minutes }
    }
    @Published var helperReady = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    var onChange: (() -> Void)?
    private var refreshing = false

    var statusTitle: String {
        guard let disabled else { return "Checking sleep status" }
        return disabled ? "Wide awake." : "Ready to nap."
    }

    func configureFirstLaunch() {
        guard !Preferences().didConfigureLogin else { return }
        setLogin(true)
        if loginEnabled || loginNeedsApproval { Preferences().didConfigureLogin = true }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            syncLogin()
        } catch { self.error = "Launch at login: \(error.localizedDescription)" }
    }

    func refresh() {
        syncLogin()
        helperReady = (try? HelperClient().installed) ?? false
        guard !refreshing, !busy else { return }
        refreshing = true
        Task {
            do {
                let output = try await Self.run("/usr/bin/pmset", ["-g"])
                disabled = try SleepStatus(output: output).disabled
                deadline = (try? Data(contentsOf: URL(fileURLWithPath: SleepCommands.plistPath)))
                    .flatMap { SleepCommands.deadline(from: $0) }
            } catch { self.error = error.localizedDescription; disabled = nil }
            refreshing = false
            onChange?()
        }
    }

    func start() { change(minutes: minutes) }

    func stop() { change(minutes: -1) }

    func installHelper() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                let client = try HelperClient()
                let script = SleepCommands.appleScript(for: try client.installationCommand())
                    .replacingOccurrences(of: "NoNappa needs permission to change sleep settings and schedule automatic sleep restoration.",
                                          with: "Install NoNappa’s sleep helper once to enable password-free sleep controls for this app and user.")
                _ = try await Self.run("/usr/bin/osascript", ["-e", script])
                try await client.ping()
                helperReady = true
            } catch { self.error = error.localizedDescription }
            busy = false
            refresh()
        }
    }

    func quit() {
        guard disabled == true else { NSApp.terminate(nil); return }
        let alert = NSAlert()
        alert.messageText = "Your Mac is still awake"
        alert.informativeText = deadline != nil
            ? "The timer will restore sleep even after NoNappa quits. You can also restore sleep now."
            : "Sleep is disabled without a NoNappa timer. Restore sleep now, or leave the current setting as it is."
        alert.addButton(withTitle: "Restore Sleep & Quit")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Keep Awake & Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: change(minutes: -1, quitAfter: true)
        case .alertThirdButtonReturn: NSApp.terminate(nil)
        default: break
        }
    }

    private func change(minutes: Int, quitAfter: Bool = false) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                let client = try HelperClient()
                guard client.installed else { throw AppError.message("Enable one-click controls first. This needs administrator approval only once per app build.") }
                try await client.change(minutes: minutes)
                if quitAfter { NSApp.terminate(nil) }
            } catch {
                let message = error.localizedDescription
                self.error = message.contains("(-128)") ? "Cancelled. Your sleep setting hasn’t changed." : message
            }
            busy = false
            refresh()
        }
    }

    private func syncLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.standardOutput = pipe
            task.standardError = pipe
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard task.terminationStatus == 0 else { throw AppError.message(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return output
        }.value
    }
}

struct Panel: View {
    @ObservedObject var model: SleepModel
    private let lime = Color(red: 0.78, green: 0.94, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: Mascot.image(size: NSSize(width: 48, height: 44)))
                    .interpolation(.none).foregroundStyle(lime)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NoNappa").font(.system(size: 24, weight: .heavy, design: .rounded))
                    Text("LID DOWN. GAME ON.").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(lime)
                }
                Spacer()
                Circle().fill(model.disabled == true ? lime : Color.gray).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.statusTitle).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(statusDetail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                if model.disabled == true, let end = model.deadline {
                    HStack {
                        Image(systemName: "timer")
                        if end > Date() {
                            Text(end, style: .timer).monospacedDigit()
                        } else {
                            Text("Restoring sleep…")
                        }
                        Spacer()
                        Text(end > Date() ? "LEFT" : "").font(.system(size: 9, weight: .bold)).tracking(1.5)
                    }.foregroundStyle(lime).padding(.top, 5)
                }
            }
            Divider().overlay(.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 10) {
                Text("RESTORE SLEEP AFTER").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 5) {
                    ForEach(Preferences.durations, id: \.self) { minutes in
                        Button(minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h") { model.minutes = minutes }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(model.minutes == minutes ? lime : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(model.minutes == minutes ? .black : .white.opacity(0.7))
                            .accessibilityLabel("\(minutes) minutes")
                    }
                }.disabled(model.busy)
                Button { model.minutes = 0 } label: {
                    HStack {
                        Image(systemName: "infinity")
                        Text("Until I turn it off")
                        Spacer()
                        if model.minutes == 0 { Image(systemName: "checkmark") }
                    }.font(.system(size: 12, weight: .medium)).padding(10)
                }.buttonStyle(.plain)
                    .background(model.minutes == 0 ? lime.opacity(0.18) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(model.minutes == 0 ? lime : .white.opacity(0.7)).disabled(model.busy)
                Button { model.start() } label: {
                    HStack {
                        Image(systemName: model.busy ? "hourglass" : "sun.max.fill")
                        Text(model.busy ? "Waiting for macOS…" : model.minutes == 0 ? "Keep awake indefinitely" : model.disabled == true ? "Start a fresh timer" : "Keep my Mac awake")
                    }.font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.plain).background(lime, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.black)
                    .disabled(model.busy || model.disabled == nil)
                if model.disabled == true {
                    Button("Restore sleep now") { model.stop() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 3).disabled(model.busy)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                if model.helperReady {
                    Label("One-click controls enabled", systemImage: "checkmark.shield")
                        .font(.system(size: 11)).foregroundStyle(lime)
                } else {
                    Button("Enable one-click controls…") { model.installHelper() }
                        .disabled(model.busy).font(.system(size: 12, weight: .semibold))
                    Text("One administrator approval. No passwords for everyday toggles.")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).tint(lime)
                if model.loginNeedsApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .font(.system(size: 11))
                }
                Text("Your duration is saved. Timed sessions restore sleep even if you quit. Indefinite sessions stay on until you restore sleep.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Refresh status") { model.error = nil; model.refresh() }
                Spacer()
                Button("Quit") { model.quit() }.disabled(model.busy)
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(24).frame(width: 340)
        .background(Color(red: 0.075, green: 0.085, blue: 0.075))
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private var statusDetail: String {
        guard let disabled = model.disabled else { return "Reading your Mac’s current power settings." }
        if !disabled { return "Start a session to keep working with the lid closed." }
        if model.deadline == nil { return "Sleep is disabled with no timer. Your Mac stays awake until you restore sleep." }
        return "Your Mac stays awake, even with the lid closed. Sleep returns when the timer ends."
    }
}

enum Mascot {
    static func image(size: NSSize) -> NSImage {
        let pixels = Bundle.main.url(forResource: "mark", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([[Double]].self, from: $0) } ?? []
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = min(rect.width / 24, rect.height / 22)
            for pixel in pixels where pixel.count == 3 {
                let cell = NSRect(x: pixel[0] * scale, y: (21 - pixel[1]) * scale, width: scale, height: scale)
                if pixel[2] == 0 {
                    NSColor.clear.setFill()
                    cell.fill(using: .copy)
                } else {
                    NSColor.black.withAlphaComponent(pixel[2]).setFill()
                    cell.fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
