#if canImport(Sparkle)
@preconcurrency import Sparkle

@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = Preferences.shared.automaticUpdates
        controller.updater.automaticallyDownloadsUpdates = Preferences.shared.automaticUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomatic(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        controller.updater.automaticallyDownloadsUpdates = enabled
    }
}
#else
@preconcurrency import AppKit

/// Direct local builds can run without resolving Sparkle. Packaged builds still
/// link Sparkle through SwiftPM; the fallback keeps UI/runtime verification
/// possible while the secure public update channel is intentionally deferred.
@MainActor
final class UpdaterController {
    init() {}

    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Updates are not configured in this build"
        alert.informativeText = "Download a newer release manually until the signed update channel is enabled."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func setAutomatic(_ enabled: Bool) {}
}
#endif
