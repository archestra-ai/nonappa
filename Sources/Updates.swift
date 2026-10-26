import AppKit
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheck = false
    @Published var automaticallyChecks = false
    @Published var automaticallyInstalls = false
    @Published private(set) var allowsAutomaticInstall = false
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?

    init(enabled: Bool) {
        // Fixture previews and unconfigured developer builds never contact the feed.
        guard enabled,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyInstalls)
        controller.updater.publisher(for: \.allowsAutomaticUpdates).assign(to: &$allowsAutomaticInstall)
    }

    var configured: Bool { controller != nil }
    func check() { controller?.checkForUpdates(nil) }
    func setAutomaticInstalls(_ enabled: Bool) { controller?.updater.automaticallyDownloadsUpdates = enabled }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    #else
    // Ad-hoc builds retain hardened runtime without loading third-party code.
    // Production builds link Sparkle and sign all code with one Developer ID.
    init(enabled: Bool) {}
    var configured: Bool { false }
    func check() {}
    func setAutomaticInstalls(_ enabled: Bool) {}
    func setAutomaticChecks(_ enabled: Bool) {}
    #endif
}
