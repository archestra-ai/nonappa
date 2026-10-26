import AppKit
import SwiftUI
import ServiceManagement

#if !NONAPPA_MODEL_TESTS
@main
struct NoNappaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let model = SleepModel(previewState: {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-state"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }())
    private var previewWindow: NSWindow?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 28)
        item.button?.image = Mascot.image(size: NSSize(width: 22, height: 20))
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("NoNappa sleep controls")
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 260)
        popover.contentViewController = NSHostingController(rootView: Panel(model: model))
        model.onChange = { [weak self] in self?.updateStatus() }
        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        updateStatus()
        if model.isPreview {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--snapshot-directory"), args.indices.contains(index + 1) {
                snapshotPreviews(to: args[index + 1])
                NSApp.terminate(nil)
            } else {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "NoNappa — Safe UI Preview"
                let content = NSHostingView(rootView: Panel(model: model))
                window.contentView = content
                window.setContentSize(content.fittingSize)
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                previewWindow = window
            }
        }
    }

    private func snapshotPreviews(to directory: String) {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for state in ["normal", "awake", "timed", "error", "setup", "busy"] {
                let view = NSHostingView(rootView: Panel(model: SleepModel(previewState: state)))
                let size = view.fittingSize
                view.frame = NSRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(state).png"))
            }
        } catch { NSLog("Preview snapshot failed: %@", error.localizedDescription) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu()
            let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login.target = self
            login.state = model.loginEnabled ? .on : .off
            login.isEnabled = !model.busy
            if model.loginNeedsApproval {
                let approve = menu.addItem(withTitle: "Approve Login Item…", action: #selector(approveLogin), keyEquivalent: "")
                approve.target = self
            }
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit NoNappa", action: #selector(quit), keyEquivalent: "q")
            quit.target = self
            quit.isEnabled = !model.busy
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    @objc private func toggleLogin() { model.setLogin(!model.loginEnabled) }
    @objc private func approveLogin() { if !model.isPreview { SMAppService.openSystemSettingsLoginItems() } }
    @objc private func quit() { model.quit() }

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

// Keep OS mutations at one boundary; previews and model tests use in-memory fixtures.
struct SleepBackend {
    var read: () async throws -> String
    var deadline: () -> Date?
    var change: (Int) async throws -> Void

    static var live: Self {
        Self(read: { try await SleepModel.run("/usr/bin/pmset", ["-g"]) },
             deadline: { (try? Data(contentsOf: URL(fileURLWithPath: SleepCommands.plistPath))).flatMap { SleepCommands.deadline(from: $0) } },
             change: { minutes in
                 let client = try HelperClient()
                 guard client.installed else { throw AppError.message("Set up sleep controls first. Administrator approval is required for this app build.") }
                 try await client.change(minutes: minutes)
             })
    }
}

final class PreviewSleepBackend {
    var disabled: Bool
    var deadline: Date?
    var failure: String?
    init(state: String) {
        disabled = ["awake", "timed", "busy"].contains(state)
        deadline = state == "timed" ? Date().addingTimeInterval(3600) : nil
        failure = state == "error" ? "Couldn’t read the Mac’s sleep setting." : nil
    }
    var backend: SleepBackend {
        SleepBackend(read: { [self] in
            if let failure { throw AppError.message(failure) }
            return "System-wide power settings:\n SleepDisabled \(disabled ? 1 : 0)"
        }, deadline: { [self] in deadline }, change: { [self] minutes in
            if let failure { throw AppError.message(failure) }
            disabled = minutes != -1
            deadline = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        })
    }
}

@MainActor
final class SleepModel: ObservableObject {
    @Published var disabled: Bool?
    @Published var deadline: Date?
    @Published var busy = false
    @Published var error: String?
    @Published var minutes: Int {
        didSet { preferences.minutes = minutes }
    }
    let isPreview: Bool
    private let backend: SleepBackend
    private let preferences: Preferences
    private var statusReadError: String?

    init(previewState: String? = nil, preferences: Preferences? = nil, backend: SleepBackend? = nil) {
        isPreview = previewState != nil
        self.backend = backend ?? previewState.map { PreviewSleepBackend(state: $0).backend } ?? .live
        self.preferences = preferences ?? (previewState == nil ? Preferences() : Preferences(defaults: UserDefaults(suiteName: "nonappa-ui-preview")!))
        minutes = self.preferences.minutes
        if let state = previewState {
            disabled = state == "error" ? nil : ["awake", "timed", "busy"].contains(state)
            deadline = state == "timed" ? Date().addingTimeInterval(3600) : nil
            helperReady = state != "setup"
            busy = state == "busy"
            error = state == "error" ? "Couldn’t read the Mac’s sleep setting." : nil
        }
    }
    @Published var helperReady = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    var onChange: (() -> Void)?
    private var refreshing = false

    var statusTitle: String {
        guard let disabled else { return statusReadError != nil || error != nil ? "Status unavailable." : "Checking sleep status" }
        return disabled ? "Wide awake." : "Ready to nap."
    }

    func setLogin(_ enabled: Bool) {
        guard !isPreview else { loginEnabled = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            syncLogin()
        } catch { self.error = "Launch at login: \(error.localizedDescription)" }
    }

    func refresh() { Task { await readStatus() } }

    func readStatus() async {
        guard !refreshing, !busy else { return }
        if !isPreview {
            syncLogin()
            helperReady = (try? HelperClient().installed) ?? false
        }
        refreshing = true
        do {
            disabled = try SleepStatus(output: await backend.read()).disabled
            if error == statusReadError { error = nil }
            statusReadError = nil
            deadline = disabled == true ? backend.deadline() : nil
        } catch {
            self.error = error.localizedDescription
            statusReadError = self.error
            disabled = nil
            deadline = nil
        }
        refreshing = false
        onChange?()
    }

    func start() { Task { await change(minutes: minutes) } }

    func stop() { Task { await change(minutes: -1) } }

    func installHelper() {
        guard !isPreview else { helperReady = true; return }
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
        guard !isPreview else { NSApp.terminate(nil); return }
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
        case .alertFirstButtonReturn: Task { await change(minutes: -1, quitAfter: true) }
        case .alertThirdButtonReturn: NSApp.terminate(nil)
        default: break
        }
    }

    func change(minutes: Int, quitAfter: Bool = false) async {
        guard !busy, disabled != nil, helperReady else { return }
        busy = true
        error = nil
        do {
            try await backend.change(minutes)
            if quitAfter { NSApp.terminate(nil) }
        } catch {
            let message = error.localizedDescription
            self.error = message.contains("(-128)") ? "Cancelled. Your sleep setting hasn’t changed." : message
        }
        busy = false
        await readStatus()
    }

    private func syncLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    nonisolated static func run(_ executable: String, _ arguments: [String]) async throws -> String {
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Image(nsImage: Mascot.image(size: NSSize(width: 32, height: 30)))
                    .interpolation(.none).foregroundStyle(lime).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NoNappa").font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("LID DOWN. GAME ON.")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1.3).foregroundStyle(lime)
                }
                Spacer()
                Menu {
                    Toggle("Launch at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    if model.loginNeedsApproval {
                        Button("Approve Login Item…") { if !model.isPreview { SMAppService.openSystemSettingsLoginItems() } }
                    }
                    if !model.helperReady { Button("Set Up Sleep Controls…") { model.installHelper() } }
                    if model.disabled == true, model.helperReady {
                        Menu("Change Duration") {
                            ForEach(Preferences.durations, id: \.self) { minutes in
                                Button(durationTitle(minutes)) { model.minutes = minutes; model.start() }
                            }
                            if model.deadline != nil {
                                Button("Until I Stop") { model.minutes = 0; model.start() }
                            }
                        }
                    }
                    Divider()
                    Button("Quit NoNappa") { model.quit() }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Settings and Quit").disabled(model.busy)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.statusTitle).font(.system(size: 27, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.updatesFrequently)
                if model.disabled == true {
                    if let end = model.deadline {
                        HStack(spacing: 5) {
                            Image(systemName: "timer")
                            if end > Date() { Text(end, style: .timer).monospacedDigit(); Text("remaining") }
                            else { Text("Restoring sleep…") }
                        }.font(.system(size: 12)).foregroundStyle(lime)
                    } else {
                        Text("Until you stop").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            if model.disabled == false {
                HStack {
                    Text("Keep awake for").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Menu(durationTitle(model.minutes)) {
                        ForEach(Preferences.durations + [0], id: \.self) { minutes in
                            Button { model.minutes = minutes } label: {
                                if model.minutes == minutes { Label(durationTitle(minutes), systemImage: "checkmark") }
                                else { Text(durationTitle(minutes)) }
                            }
                        }
                    }.fixedSize().accessibilityLabel("Keep awake duration").disabled(model.busy)
                }
            }
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: primaryAction) {
                HStack(spacing: 7) {
                    if model.busy { ProgressView().controlSize(.small).tint(.black) }
                    Text(primaryTitle)
                }.font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.plain).background(lime, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.black).disabled(model.busy || (model.disabled == nil && model.error == nil))
            if !model.helperReady, model.disabled != nil {
                Text("Administrator approval required").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(20).frame(width: 300)
        .background(Color(red: 0.075, green: 0.085, blue: 0.075))
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private var primaryTitle: String {
        if model.busy { return "Updating…" }
        if model.disabled == nil { return model.error == nil ? "Checking…" : "Try Again" }
        if !model.helperReady { return "Set Up Sleep Controls…" }
        return model.disabled == true ? "Restore Sleep" : "Keep Awake"
    }

    private func primaryAction() {
        if model.disabled == nil { model.refresh() }
        else if !model.helperReady { model.installHelper() }
        else if model.disabled == true { model.stop() }
        else { model.start() }
    }

    private func durationTitle(_ minutes: Int) -> String {
        if minutes == 0 { return "Until I stop" }
        return minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
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
