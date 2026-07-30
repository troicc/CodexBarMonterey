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
