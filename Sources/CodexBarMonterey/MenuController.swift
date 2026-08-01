@preconcurrency import AppKit

@MainActor
final class MenuController: NSObject {
    private let client: CLIClient
    private let updater: UpdaterController
    private let store: DashboardStore
    private let popover: DashboardPopoverController
    private let detailPanel: ProviderDetailPanelController

    private var mergedItem: NSStatusItem?
    private var providerItems: [String: NSStatusItem] = [:]
    private var buttonProviders: [ObjectIdentifier: String] = [:]
    private var refreshTimer: Timer?

    private lazy var settings = SettingsWindowController(client: client, updater: updater)
    private lazy var details = DetailsWindowController(store: store)

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
        let dashboardStore = DashboardStore(client: client)
        self.store = dashboardStore
        self.popover = DashboardPopoverController(store: dashboardStore)
        self.detailPanel = ProviderDetailPanelController(store: dashboardStore)
        super.init()

        store.onOpenSettings = { [weak self] in
            self?.popover.close()
            self?.settings.show(selectedProviderID: self?.store.selectedSnapshot?.provider)
        }
        store.onOpenAllDetails = { [weak self] in
            self?.popover.close()
            self?.details.show()
        }
        store.onOpenProviderDetails = { [weak self] snapshotID in
            guard let self = self,
                  let snapshot = self.store.snapshots.first(where: { $0.id == snapshotID })
            else { return }
            self.detailPanel.show(snapshot: snapshot)
        }
        store.onQuit = { NSApp.terminate(nil) }
        store.onRefreshStateChanged = { [weak self] in
            self?.rebuildStatusItems()
            self?.renderStatusItems()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .preferencesChanged,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerConfigurationChanged(_:)),
            name: .providerConfigurationChanged,
            object: nil)

        rebuildStatusItems()
        renderStatusItems()
        installApplicationMenu()
        scheduleTimer()
        Task { await refresh() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func preferencesChanged() {
        rebuildStatusItems()
        scheduleTimer()
        renderStatusItems()
    }

    @objc private func providerConfigurationChanged(_: Notification) {
        Task { await refresh() }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Preferences.shared.refreshInterval,
            repeats: true)
        { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func refresh() async {
        await store.refresh()
    }

    private func rebuildStatusItems() {
        buttonProviders.removeAll()
        if Preferences.shared.mergeIcons || store.snapshots.isEmpty {
            providerItems.values.forEach { NSStatusBar.system.removeStatusItem($0) }
            providerItems.removeAll()
            if mergedItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "codexbar-monterey-merged"
                configureAction(for: item, providerID: nil)
                mergedItem = item
            }
        } else {
            if let mergedItem = mergedItem {
                NSStatusBar.system.removeStatusItem(mergedItem)
                self.mergedItem = nil
            }
            let desired = Set(store.snapshots.map(\.id))
            let staleKeys = providerItems.keys.filter { !desired.contains($0) }
            for key in staleKeys {
                guard let stale = providerItems.removeValue(forKey: key) else { continue }
                NSStatusBar.system.removeStatusItem(stale)
            }
            for snapshot in store.snapshots where providerItems[snapshot.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "codexbar-monterey-\(snapshot.provider)-\(StableIdentifier.hash(snapshot.id))"
                providerItems[snapshot.id] = item
            }
            for snapshot in store.snapshots {
                if let item = providerItems[snapshot.id] {
                    configureAction(for: item, providerID: snapshot.id)
                }
            }
        }
    }

    private func configureAction(for item: NSStatusItem, providerID: String?) {
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let providerID = providerID { buttonProviders[ObjectIdentifier(button)] = providerID }
    }

    private func renderStatusItems() {
        if let mergedItem = mergedItem {
            configureButton(mergedItem.button, snapshots: store.snapshots)
        }
        for snapshot in store.snapshots {
            if let item = providerItems[snapshot.id] {
                configureButton(item.button, snapshots: [snapshot])
            }
        }
    }

    private func configureButton(_ button: NSStatusBarButton?, snapshots: [ProviderSnapshot]) {
        guard let button = button else { return }
        let highest = snapshots.compactMap(\.maximumUsedPercent).max()
        if Preferences.shared.showPercentage, let highest = highest {
            button.title = String(format: "%.0f%%", highest)
            button.image = nil
        } else {
            button.title = ""
            button.image = meterImage(
                percent: highest ?? 0,
                failed: !snapshots.isEmpty && snapshots.allSatisfy(\.isFailed))
            button.image?.isTemplate = true
        }
        if store.isRefreshing {
            button.toolTip = "Refreshing…"
        } else if let error = store.lastError {
            button.toolTip = "Refresh failed — showing saved data: \(error)"
        } else {
            button.toolTip = snapshots.isEmpty ? "CodexBar Monterey" : snapshots.map { snapshot in
                snapshot.accountDisplayName.map { "\(snapshot.displayName) — \($0)" } ?? snapshot.displayName
            }.joined(separator: ", ")
        }
        let providerDescription = snapshots.isEmpty ? "CodexBar Monterey" : snapshots.map { snapshot in
            snapshot.accountDisplayName.map { "\(snapshot.displayName), \($0)" } ?? snapshot.displayName
        }.joined(separator: ", ")
        button.setAccessibilityLabel(providerDescription)
        if store.isRefreshing {
            button.setAccessibilityValue("Refreshing")
        } else if store.lastError != nil {
            button.setAccessibilityValue("Refresh failed; showing saved data")
        } else if let highest = highest {
            button.setAccessibilityValue(String(format: "%.0f percent used", highest))
        } else {
            button.setAccessibilityValue("Usage unavailable")
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let providerID = buttonProviders[ObjectIdentifier(sender)]
        if let event = NSApp.currentEvent {
            let isContextClick = event.type == .rightMouseUp ||
                (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
            if isContextClick {
                showContextMenu(for: sender, providerID: providerID, event: event)
                return
            }
        }
        popover.toggle(relativeTo: sender, select: providerID)
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)

        let applicationMenu = NSMenu(title: "CodexBar Monterey")
        applicationItem.submenu = applicationMenu

        let about = NSMenuItem(
            title: "About CodexBar Monterey",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        about.target = NSApp
        applicationMenu.addItem(about)

        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem(
            title: "Settings…",
            action: #selector(openSettingsMenuItem),
            keyEquivalent: ","))
        applicationMenu.addItem(menuItem(
            title: "Refresh Now",
            action: #selector(refreshMenuItem),
            keyEquivalent: "r"))
        applicationMenu.addItem(menuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesMenuItem)))

        applicationMenu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit CodexBar Monterey",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit)
        NSApp.mainMenu = mainMenu
    }

    private func showContextMenu(
        for button: NSStatusBarButton,
        providerID: String?,
        event: NSEvent
    ) {
        let menu = NSMenu(title: "CodexBar Monterey")
        if let providerID = providerID,
           let snapshot = store.snapshots.first(where: { $0.id == providerID })
        {
            let account = snapshot.accountDisplayName.map { " — \($0)" } ?? ""
            let header = NSMenuItem(title: "\(snapshot.displayName)\(account)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }
        menu.addItem(menuItem(
            title: store.isRefreshing ? "Refreshing…" : "Refresh Now",
            action: #selector(refreshMenuItem),
            keyEquivalent: "r",
            enabled: !store.isRefreshing))
        menu.addItem(menuItem(
            title: "Settings…",
            action: #selector(openSettingsMenuItem),
            keyEquivalent: ","))
        menu.addItem(menuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesMenuItem)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", action: #selector(quitMenuItem), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : [.command]
        item.isEnabled = enabled
        return item
    }

    @objc private func refreshMenuItem() {
        Task { await refresh() }
    }

    @objc private func openSettingsMenuItem() {
        popover.close()
        settings.show(selectedProviderID: store.selectedSnapshot?.provider)
    }

    @objc private func checkForUpdatesMenuItem() {
        updater.checkForUpdates()
    }

    @objc private func quitMenuItem() {
        NSApp.terminate(nil)
    }

    private func meterImage(percent: Double, failed: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let used = max(0, min(100, percent)) / 100
        let barWidth: CGFloat = 5
        let gap: CGFloat = 2
        let baseY: CGFloat = 2
        let maxHeight: CGFloat = 12
        NSColor.labelColor.withAlphaComponent(failed ? 0.22 : 0.18).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 3, y: baseY, width: barWidth, height: maxHeight),
            xRadius: 1.5,
            yRadius: 1.5).fill()
        NSBezierPath(
            roundedRect: NSRect(x: 3 + barWidth + gap, y: baseY, width: barWidth, height: maxHeight),
            xRadius: 1.5,
            yRadius: 1.5).fill()
        NSColor.labelColor.setFill()
        let fillHeight = max(1, maxHeight * used)
        NSBezierPath(
            roundedRect: NSRect(x: 3, y: baseY, width: barWidth, height: fillHeight),
            xRadius: 1.5,
            yRadius: 1.5).fill()
        NSBezierPath(
            roundedRect: NSRect(
                x: 3 + barWidth + gap,
                y: baseY,
                width: barWidth,
                height: max(1, maxHeight * min(1, used * 0.72))),
            xRadius: 1.5,
            yRadius: 1.5).fill()
        image.unlockFocus()
        return image
    }
}
