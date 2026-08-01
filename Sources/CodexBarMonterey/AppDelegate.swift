@preconcurrency import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuController?
    private var updaterController: UpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let updater = UpdaterController()
        updaterController = updater
        menuController = MenuController(client: CLIClient(), updater: updater)

        if let outputPath = ProcessInfo.processInfo.environment["CODEXBAR_MONTEREY_UI_SMOKE_OUTPUT"],
           !outputPath.isEmpty
        {
            Task { @MainActor [weak self] in
                let report = await self?.menuController?.runtimeSmokeReport()
                    ?? "FAIL: menu controller unavailable"
                do {
                    try (report + "\n").write(
                        toFile: outputPath,
                        atomically: true,
                        encoding: .utf8)
                } catch {
                    NSLog("Could not write UI smoke report: %@", error.localizedDescription)
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
