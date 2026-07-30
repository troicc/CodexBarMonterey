@preconcurrency import AppKit
import SwiftUI

@MainActor
final class ProviderDetailPanelController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 590),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { nil }

    func show(dashboard: ProviderDashboard) {
        guard let window else { return }
        window.contentViewController = NSHostingController(rootView: ProviderDetailPanelView(dashboard: dashboard))
        window.title = "\(dashboard.title) Details"
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.maxX - window.frame.width - 28,
                y: visible.maxY - window.frame.height - 58)
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
