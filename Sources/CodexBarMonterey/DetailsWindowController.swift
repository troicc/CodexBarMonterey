@preconcurrency import AppKit
import SwiftUI

@MainActor
final class DetailsWindowController: NSObject {
    private let store: DashboardStore
    private let popover = NSPopover()

    init(store: DashboardStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = true
    }

    var isShown: Bool { popover.isShown }

    func show(relativeTo button: NSStatusBarButton) {
        let available = button.window?.screen?.visibleFrame.size ?? NSSize(width: 1024, height: 768)
        popover.contentSize = NSSize(width: min(620, available.width - 40), height: min(680, available.height - 70))
        popover.contentViewController = NSHostingController(rootView: AllProvidersDashboardView(store: store))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { popover.performClose(nil) }
}
