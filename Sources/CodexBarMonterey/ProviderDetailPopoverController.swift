@preconcurrency import AppKit
import SwiftUI

@MainActor
final class ProviderDetailPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let store: DashboardStore

    init(store: DashboardStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 560)
    }

    var isShown: Bool { popover.isShown }

    func show(snapshot: ProviderSnapshot, relativeTo button: NSStatusBarButton) {
        store.select(snapshot)
        popover.contentViewController = NSHostingController(
            rootView: LiveProviderDetailPopoverView(store: store, snapshotID: snapshot.id))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        popover.performClose(nil)
    }
}
