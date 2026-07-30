@preconcurrency import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuController?
    private var updaterController: UpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let updater = UpdaterController()
        updaterController = updater
        menuController = MenuController(client: CLIClient(), updater: updater)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
