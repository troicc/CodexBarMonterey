import Foundation

@MainActor
enum LaunchAtLoginController {
    private static var label: String {
        Bundle.main.bundleIdentifier ?? "com.codexbar.monterey"
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try FileManager.default.createDirectory(
                    at: plistURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                let appPath = Bundle.main.bundlePath
                let plist: [String: Any] = [
                    "Label": label,
                    "ProgramArguments": ["/usr/bin/open", "-gj", appPath],
                    "RunAtLoad": true,
                    "KeepAlive": false,
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: plistURL, options: .atomic)
                runLaunchctl(["load", "-w", plistURL.path])
            } else {
                runLaunchctl(["unload", "-w", plistURL.path])
                try? FileManager.default.removeItem(at: plistURL)
            }
        } catch {
            NSLog("Launch-at-login update failed: %@", error.localizedDescription)
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
