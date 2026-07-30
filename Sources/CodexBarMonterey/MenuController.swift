@preconcurrency import AppKit

@MainActor
final class MenuController: NSObject {
    private let client: CLIClient
    private let updater: UpdaterController
    private let store: DashboardStore
    private let popover: DashboardPopoverController
    private let detailPanel = ProviderDetailPanelController()

    private var mergedItem: NSStatusItem?
    private var providerItems: [String: NSStatusItem] = [:]
    private var buttonProviders: [ObjectIdentifier: String] = [:]
    private var refreshTimer: Timer?

    private lazy var settings = SettingsWindowController(client: client, updater: updater)
    private lazy var details = DetailsWindowController(store: store)

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
        self.store = DashboardStore(client: client)
        self.popover = DashboardPopoverController(store: store)
        super.init()

        store.onOpenSettings = { [weak self] in
            self?.popover.close()
            self?.settings.show(selectedProviderID: self?.store.selectedSnapshot?.provider)
        }
        store.onOpenAllDetails = { [weak self] in
            self?.popover.close()
            self?.details.showUsage(provider: nil, displayName: nil)
        }
        store.onOpenProviderDetails = { [weak self] providerID in
            guard let self,
                  let snapshot = self.store.snapshots.first(where: { $0.provider == providerID || $0.id == providerID })
            else { return }
            self.detailPanel.show(dashboard: self.store.dashboard(for: snapshot))
        }
        store.onCheckUpdates = { [weak self] in self?.updater.checkForUpdates() }
        store.onQuit = { NSApp.terminate(nil) }

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

    @objc private func providerConfigurationChanged(_ notification: Notification) {
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
        rebuildStatusItems()
        renderStatusItems()
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
            if let mergedItem {
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
                item.autosaveName = "codexbar-monterey-\(snapshot.provider)"
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
        if let providerID { buttonProviders[ObjectIdentifier(button)] = providerID }
    }

    private func renderStatusItems() {
        if let mergedItem {
            configureButton(mergedItem.button, snapshots: store.snapshots)
        }
        for snapshot in store.snapshots {
            if let item = providerItems[snapshot.id] {
                configureButton(item.button, snapshots: [snapshot])
            }
        }
    }

    private func configureButton(_ button: NSStatusBarButton?, snapshots: [ProviderSnapshot]) {
        guard let button else { return }
        let highest = snapshots.compactMap(\.maximumUsedPercent).max()
        if Preferences.shared.showPercentage, let highest {
            button.title = String(format: "%.0f%%", highest)
            button.image = nil
        } else {
            button.title = ""
            button.image = meterImage(percent: highest ?? 0, failed: snapshots.allSatisfy(\.isFailed))
            button.image?.isTemplate = true
        }
        if store.isRefreshing {
            button.toolTip = "Refreshing…"
        } else if let error = store.lastError {
            button.toolTip = error
        } else {
            button.toolTip = snapshots.isEmpty ? "CodexBar Monterey" : snapshots.map(\.displayName).joined(separator: ", ")
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let providerID = buttonProviders[ObjectIdentifier(sender)]
        popover.toggle(relativeTo: sender, select: providerID)
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
