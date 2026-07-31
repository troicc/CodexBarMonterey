@preconcurrency import AppKit
import SwiftUI

@MainActor
final class DetailsWindowController: NSWindowController {
    private let store: DashboardStore

    init(store: DashboardStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CodexBar Provider Details"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func showUsage(provider: String?, displayName: String?) {
        guard let window = window else { return }
        window.title = displayName.map { "\($0) — Full Usage Details" } ?? "All Enabled Providers — Full Usage Details"
        window.contentViewController = NSHostingController(
            rootView: AllProvidersDashboardView(store: store, selectedProvider: provider))
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showCost(provider: String?, displayName: String?) {
        // The graphical dashboard now merges quota, spend, token, and request
        // histories into one original-style view instead of exposing raw CLI text.
        showUsage(provider: provider, displayName: displayName)
    }
}
