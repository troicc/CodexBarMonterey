@preconcurrency import AppKit
import SwiftUI

@MainActor
final class ProviderDetailPanelController: NSWindowController {
    private let store: DashboardStore
    private var hasInitialPosition = false

    init(store: DashboardStore) {
        self.store = store
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 430),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let frameName = "CodexBarMonterey.ProviderDetailPanel"
        let restoredFrame = panel.setFrameUsingName(frameName)
        panel.setFrameAutosaveName(frameName)
        super.init(window: panel)
        hasInitialPosition = restoredFrame
    }

    required init?(coder: NSCoder) { nil }

    func show(snapshot: ProviderSnapshot) {
        guard let window = window else { return }
        window.contentViewController = NSHostingController(
            rootView: LiveProviderDetailPanelView(store: store, snapshotID: snapshot.id))
        let accountSuffix = snapshot.accountDisplayName.map { " — \($0)" } ?? ""
        window.title = "\(snapshot.displayName)\(accountSuffix) Details"
        if !hasInitialPosition {
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let origin = NSPoint(
                    x: visible.maxX - window.frame.width - 28,
                    y: visible.maxY - window.frame.height - 58)
                window.setFrameOrigin(origin)
            } else {
                window.center()
            }
            hasInitialPosition = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
