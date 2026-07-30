@preconcurrency import AppKit
import SwiftUI

@MainActor
final class DashboardPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    let store: DashboardStore

    init(store: DashboardStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 328, height: 520)
        popover.contentViewController = NSHostingController(rootView: DashboardPopoverView(store: store))
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton, select providerID: String? = nil) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let providerID { store.selectProviderID(providerID) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            if store.snapshots.isEmpty { await store.refresh() }
            else { await store.enrichSelectedDashboard() }
        }
    }

    func close() {
        popover.performClose(nil)
    }
}
