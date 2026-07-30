@preconcurrency import AppKit

@main
enum CodexBarMontereyApp {
    // AppKit is main-thread confined. Declaring the executable entry point as
    // MainActor-isolated satisfies Swift 6.3's stricter actor checking while
    // preserving a conventional NSApplication run loop on macOS 12.
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        // NSApplication.delegate is not guaranteed to retain its delegate.
        // The local remains alive for the complete blocking run loop.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
