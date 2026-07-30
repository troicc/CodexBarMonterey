@preconcurrency import AppKit

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let client: CLIClient
    private let updater: UpdaterController
    private var mergedItem: NSStatusItem?
    private var providerItems: [String: NSStatusItem] = [:]
    private var snapshots: [ProviderSnapshot] = []
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var lastError: Error?
    private lazy var settings = SettingsWindowController(client: client, updater: updater)
    private lazy var details = DetailsWindowController(client: client)

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: .preferencesChanged, object: nil)
        rebuildStatusItems()
        scheduleTimer()
        Task { await refresh() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func preferencesChanged() {
        rebuildStatusItems()
        scheduleTimer()
        render()
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Preferences.shared.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        render()
        do {
            snapshots = try await client.fetchEnabled(status: true)
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            lastError = nil
        } catch {
            lastError = error
        }
        isRefreshing = false
        rebuildStatusItems()
        render()
    }

    private func rebuildStatusItems() {
        if Preferences.shared.mergeIcons {
            providerItems.values.forEach { NSStatusBar.system.removeStatusItem($0) }
            providerItems.removeAll()
            if mergedItem == nil {
                mergedItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                mergedItem?.autosaveName = "codexbar-monterey-merged"
                mergedItem?.menu = makeMenu(for: nil)
            }
        } else {
            if let mergedItem {
                NSStatusBar.system.removeStatusItem(mergedItem)
                self.mergedItem = nil
            }
            let desired = Set(snapshots.map(\.id))
            let staleKeys = providerItems.keys.filter { !desired.contains($0) }
            for key in staleKeys {
                guard let item = providerItems.removeValue(forKey: key) else { continue }
                NSStatusBar.system.removeStatusItem(item)
            }
            for snapshot in snapshots where providerItems[snapshot.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "codexbar-monterey-\(snapshot.provider)"
                item.menu = makeMenu(for: snapshot.id)
                providerItems[snapshot.id] = item
            }
        }
    }

    private func render() {
        if let mergedItem {
            configureButton(mergedItem.button, snapshots: snapshots)
            mergedItem.menu = makeMenu(for: nil)
        }
        for snapshot in snapshots {
            guard let item = providerItems[snapshot.id] else { continue }
            configureButton(item.button, snapshots: [snapshot])
            item.menu = makeMenu(for: snapshot.id)
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
        if isRefreshing { button.toolTip = "Refreshing…" }
        else if let lastError { button.toolTip = lastError.localizedDescription }
        else { button.toolTip = snapshots.map(\.displayName).joined(separator: ", ") }
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
        let path1 = NSBezierPath(roundedRect: NSRect(x: 3, y: baseY, width: barWidth, height: maxHeight), xRadius: 1.5, yRadius: 1.5)
        NSColor.labelColor.withAlphaComponent(failed ? 0.25 : 0.20).setFill()
        path1.fill()
        let path2 = NSBezierPath(roundedRect: NSRect(x: 3 + barWidth + gap, y: baseY, width: barWidth, height: maxHeight), xRadius: 1.5, yRadius: 1.5)
        path2.fill()
        NSColor.labelColor.setFill()
        let fillHeight = max(1, maxHeight * used)
        NSBezierPath(roundedRect: NSRect(x: 3, y: baseY, width: barWidth, height: fillHeight), xRadius: 1.5, yRadius: 1.5).fill()
        NSBezierPath(roundedRect: NSRect(x: 3 + barWidth + gap, y: baseY, width: barWidth, height: max(1, maxHeight * min(1, used * 0.72))), xRadius: 1.5, yRadius: 1.5).fill()
        image.unlockFocus()
        return image
    }

    private func makeMenu(for snapshotID: String?) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let visible = snapshotID.flatMap { id in snapshots.first(where: { $0.id == id }).map { [$0] } } ?? snapshots

        if visible.isEmpty {
            let title = isRefreshing ? "Refreshing providers…" : (lastError?.localizedDescription ?? "No enabled providers")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for snapshot in visible {
                let item = NSMenuItem()
                item.view = ProviderMenuView(snapshot: snapshot)
                menu.addItem(item)
                let actions = NSMenuItem(title: snapshot.displayName, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.addItem(withTitle: "Open full provider details…", action: #selector(openProviderDetails(_:)), keyEquivalent: "")
                submenu.items.last?.representedObject = snapshot.provider
                submenu.addItem(withTitle: "Open cost details…", action: #selector(openProviderCost(_:)), keyEquivalent: "")
                submenu.items.last?.representedObject = snapshot.provider
                submenu.addItem(withTitle: "Copy provider JSON", action: #selector(copyProviderJSON(_:)), keyEquivalent: "")
                submenu.items.last?.representedObject = snapshot.id
                if let url = snapshot.status?.url {
                    submenu.addItem(withTitle: "Open status page", action: #selector(openURL(_:)), keyEquivalent: "")
                    submenu.items.last?.representedObject = url
                }
                actions.submenu = submenu
                menu.addItem(actions)
                menu.addItem(.separator())
            }
        }

        if snapshotID == nil {
            menu.addItem(withTitle: "Open all provider details…", action: #selector(openAllDetails), keyEquivalent: "d")
            menu.addItem(withTitle: "Open all cost details…", action: #selector(openAllCostDetails), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Refresh now", action: #selector(refreshAction), keyEquivalent: "r")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Check for updates…", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CodexBar Monterey", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }

    @objc private func refreshAction() { Task { await refresh() } }
    @objc private func openAllDetails() { details.showUsage(provider: nil, displayName: nil) }
    @objc private func openAllCostDetails() { details.showCost(provider: nil, displayName: nil) }
    @objc private func openProviderDetails(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? String else { return }
        details.showUsage(provider: provider, displayName: ProviderCatalog.displayName(for: provider))
    }
    @objc private func openProviderCost(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? String else { return }
        details.showCost(provider: provider, displayName: ProviderCatalog.displayName(for: provider))
    }
    @objc private func openSettings() { settings.show() }
    @objc private func checkUpdates() { updater.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func copyProviderJSON(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let json = snapshots.first(where: { $0.id == id })?.rawJSON else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}
