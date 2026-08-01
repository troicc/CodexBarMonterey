@preconcurrency import AppKit
import SwiftUI

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private static let mergedMenuContext = "__codexbar_overview__"

    private let client: CLIClient
    private let updater: UpdaterController
    private let store: DashboardStore
    private let popover: DashboardPopoverController
    private let detailPopover: ProviderDetailPopoverController
    private let alertController = ProviderAlertController()

    private var mergedItem: NSStatusItem?
    private var providerItems: [String: NSStatusItem] = [:]
    private var menuContexts: [ObjectIdentifier: String] = [:]
    private var refreshTimer: Timer?
    private var lastMenuOpenedAt: Date?
    private weak var lastStatusButton: NSStatusBarButton?
    private var lastMenuProviderID: String?

    private lazy var settings = SettingsWindowController(
        client: client,
        updater: updater,
        dashboardStore: store)
    private lazy var details = DetailsWindowController(store: store)

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
        let dashboardStore = DashboardStore(client: client)
        self.store = dashboardStore
        self.popover = DashboardPopoverController(store: dashboardStore)
        self.detailPopover = ProviderDetailPopoverController(store: dashboardStore)
        super.init()
        alertController.prepareAuthorizationIfNeeded()

        store.onOpenSettings = { [weak self] in
            self?.popover.close()
            self?.detailPopover.close()
            self?.settings.show(selectedProviderID: self?.store.selectedSnapshot?.provider)
        }
        store.onOpenAllDetails = { [weak self] in
            self?.popover.close()
            self?.details.show()
        }
        store.onOpenProviderDetails = { [weak self] snapshotID in
            guard let self = self,
                  let snapshot = self.store.snapshots.first(where: { $0.id == snapshotID }),
                  let button = self.lastStatusButton
            else { return }
            self.popover.close()
            DispatchQueue.main.async { [weak self, weak button] in
                guard let self = self, let button = button else { return }
                self.detailPopover.show(snapshot: snapshot, relativeTo: button)
            }
        }
        store.onQuit = { NSApp.terminate(nil) }
        store.onRefreshStateChanged = { [weak self] in
            self?.rebuildStatusItems()
            self?.renderStatusItems()
        }
        store.onRefreshCompleted = { [weak self] snapshots in
            guard let self = self else { return }
            self.alertController.evaluate(snapshots: snapshots, dashboards: self.store.dashboards)
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
        Task { await refresh() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
    }

    @objc private func preferencesChanged() {
        rebuildStatusItems()
        renderStatusItems()
        scheduleNextRefresh()
    }

    @objc private func providerConfigurationChanged(_: Notification) {
        Task { await refresh() }
    }

    private func refresh() async {
        await store.refresh()
        scheduleNextRefresh()
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let interval: TimeInterval
        switch Preferences.shared.refreshMode {
        case .manual:
            return
        case .fixed:
            interval = Preferences.shared.refreshInterval
        case .adaptive:
            interval = adaptiveRefreshInterval()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func adaptiveRefreshInterval(now: Date = Date()) -> TimeInterval {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 1800 }
        guard let lastMenuOpenedAt = lastMenuOpenedAt else { return 300 }
        let idle = now.timeIntervalSince(lastMenuOpenedAt)
        if idle < 10 * 60 { return 120 }
        if idle < 60 * 60 { return 300 }
        return 900
    }

    private func rebuildStatusItems() {
        menuContexts.removeAll()
        if Preferences.shared.mergeIcons || store.snapshots.isEmpty {
            providerItems.values.forEach { NSStatusBar.system.removeStatusItem($0) }
            providerItems.removeAll()
            if mergedItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "codexbar-monterey-merged"
                mergedItem = item
            }
            if let mergedItem = mergedItem {
                installNativeMenu(on: mergedItem, providerID: nil)
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
                    installNativeMenu(on: item, providerID: snapshot.id)
                }
            }
        }
    }

    private func installNativeMenu(on item: NSStatusItem, providerID: String?) {
        let menu: NSMenu
        if let existing = item.menu {
            menu = existing
        } else {
            menu = NSMenu(title: "CodexBar Monterey")
            menu.autoenablesItems = false
            menu.delegate = self
            item.menu = menu
        }
        menuContexts[ObjectIdentifier(menu)] = providerID ?? Self.mergedMenuContext
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
        let highest = snapshots.compactMap(\.headlineUsedPercent).max()
        let hasAlert = Preferences.shared.showServiceStatus && snapshots.contains(where: \.hasVisibleAlert)
        let alertPrefix = hasAlert ? "! " : ""

        switch Preferences.shared.menuBarDisplayStyle {
        case .meter:
            button.title = hasAlert ? "!" : ""
            button.image = meterImage(
                percent: highest ?? 0,
                failed: !snapshots.isEmpty && snapshots.allSatisfy(\.isFailed))
            button.image?.isTemplate = true
        case .usedPercentage:
            button.title = highest.map { alertPrefix + String(format: "%.0f%%", $0) } ?? "—"
            button.image = nil
        case .remainingPercentage:
            button.title = highest.map { alertPrefix + String(format: "%.0f%%", max(0, 100 - $0)) } ?? "—"
            button.image = nil
        case .providerIcon:
            button.title = hasAlert ? "!" : ""
            if snapshots.count == 1, let snapshot = snapshots.first {
                button.image = NSImage(
                    systemSymbolName: ProviderBrand.symbol(for: snapshot.provider),
                    accessibilityDescription: snapshot.displayName)
            } else {
                button.image = meterImage(
                    percent: highest ?? 0,
                    failed: !snapshots.isEmpty && snapshots.allSatisfy(\.isFailed))
            }
            button.image?.isTemplate = true
        }

        button.toolTip = statusItemTooltip(snapshots: snapshots)
        let providerDescription = snapshots.isEmpty ? "CodexBar Monterey" : snapshots.map { snapshot in
            snapshot.accountDisplayName.map { "\(snapshot.displayName), \($0)" } ?? snapshot.displayName
        }.joined(separator: ", ")
        button.setAccessibilityLabel(providerDescription)
        if store.isRefreshing {
            button.setAccessibilityValue("Refreshing")
        } else if store.lastError != nil {
            button.setAccessibilityValue("Refresh failed; showing saved data")
        } else if hasAlert {
            button.setAccessibilityValue("Provider needs attention")
        } else if let highest = highest {
            button.setAccessibilityValue(String(format: "%.0f percent used", highest))
        } else {
            button.setAccessibilityValue("Usage unavailable")
        }
    }

    private func statusItemTooltip(snapshots: [ProviderSnapshot]) -> String {
        if store.isRefreshing { return "CodexBar Monterey — Refreshing…" }
        if let error = store.lastError { return "Refresh failed — showing saved data: \(error)" }
        guard !snapshots.isEmpty else { return "CodexBar Monterey" }
        return snapshots.map { snapshot in
            var parts = [snapshot.displayName]
            if let account = snapshot.accountDisplayName { parts.append(account) }
            if let error = snapshot.error?.message { parts.append(error) }
            else if snapshot.serviceHealth.isIncident, let status = snapshot.status { parts.append(status.displayText) }
            else if let percent = snapshot.headlineUsedPercent {
                let label = snapshot.headlineQuotaLabel.map { "\($0) " } ?? ""
                parts.append(label + String(format: "%.0f%% used", percent))
            }
            return parts.joined(separator: " — ")
        }.joined(separator: "\n")
    }

    func menuWillOpen(_ menu: NSMenu) {
        let context = menuContexts[ObjectIdentifier(menu)] ?? Self.mergedMenuContext
        let providerID = context == Self.mergedMenuContext ? nil : context
        lastMenuProviderID = providerID
        lastStatusButton = statusItem(for: menu)?.button
        lastMenuOpenedAt = Date()
        populate(menu: menu, providerID: providerID)
        scheduleNextRefresh()

        if let providerID = providerID {
            store.selectProviderID(providerID)
        } else {
            for snapshot in store.snapshots.prefix(Preferences.shared.overviewProviderLimit) {
                Task { await store.enrich(snapshot) }
            }
        }

        if Preferences.shared.refreshOnMenuOpen,
           !store.isRefreshing,
           store.lastSuccessfulRefresh.map({ Date().timeIntervalSince($0) > 60 }) ?? true
        {
            Task { await refresh() }
        }
    }

    private func statusItem(for menu: NSMenu) -> NSStatusItem? {
        if mergedItem?.menu === menu { return mergedItem }
        return providerItems.values.first(where: { $0.menu === menu })
    }

    private func populate(menu: NSMenu, providerID: String?) {
        menu.removeAllItems()
        if let providerID = providerID,
           let snapshot = store.snapshots.first(where: { $0.id == providerID })
        {
            populateProviderMenu(menu, snapshot: snapshot, includeQuit: true)
        } else {
            populateOverviewMenu(menu)
        }
    }

    private func populateOverviewMenu(_ menu: NSMenu) {
        let worstHealth = store.snapshots.map {
            $0.error == nil ? $0.serviceHealth : ProviderServiceHealth.outage
        }.max()
        menu.addItem(hostedMenuItem(NativeMenuHeaderView(
            title: "CodexBar Monterey",
            subtitle: menuSubtitle(),
            providerID: nil,
            health: Preferences.shared.showServiceStatus ? worstHealth : nil,
            refreshing: store.isRefreshing)))

        let limit = Preferences.shared.overviewProviderLimit
        let rows = store.snapshots.prefix(limit).map { snapshot in
            NativeMenuOverviewRow(
                id: snapshot.id,
                providerID: snapshot.provider,
                title: snapshot.displayName,
                account: snapshot.accountDisplayName,
                usedPercent: snapshot.headlineUsedPercent,
                quotaLabel: snapshot.headlineQuotaLabel,
                health: snapshot.serviceHealth,
                hasError: snapshot.error != nil)
        }
        menu.addItem(hostedMenuItem(NativeMenuOverviewView(
            rows: Array(rows),
            totalCount: store.snapshots.count,
            quotaPresentation: Preferences.shared.menuQuotaPresentation,
            showAccount: Preferences.shared.showAccountInMenu,
            showStatus: Preferences.shared.showServiceStatus)))
        menu.addItem(.separator())

        if !store.snapshots.isEmpty {
            let providersItem = NSMenuItem(title: "Providers", action: nil, keyEquivalent: "")
            let providersMenu = NSMenu(title: "Providers")
            for snapshot in store.snapshots {
                let item = NSMenuItem(
                    title: providerMenuTitle(snapshot),
                    action: nil,
                    keyEquivalent: "")
                item.image = NSImage(
                    systemSymbolName: ProviderBrand.symbol(for: snapshot.provider),
                    accessibilityDescription: snapshot.displayName)
                item.image?.isTemplate = true
                let submenu = NSMenu(title: snapshot.displayName)
                populateProviderMenu(submenu, snapshot: snapshot, includeQuit: false)
                item.submenu = submenu
                providersMenu.addItem(item)
            }
            providersItem.submenu = providersMenu
            menu.addItem(providersItem)
        }

        menu.addItem(menuItem(
            title: "Open All Provider Details…",
            action: #selector(openAllDetailsMenuItem),
            symbol: "square.grid.2x2"))
        menu.addItem(.separator())
        appendCommonActions(to: menu, includeQuit: true)
    }

    private func populateProviderMenu(
        _ menu: NSMenu,
        snapshot: ProviderSnapshot,
        includeQuit: Bool
    ) {
        let dashboard = store.dashboard(for: snapshot)
        menu.addItem(hostedMenuItem(NativeMenuHeaderView(
            title: snapshot.displayName,
            subtitle: providerSubtitle(snapshot, dashboard: dashboard),
            providerID: snapshot.provider,
            health: Preferences.shared.showServiceStatus ? snapshot.serviceHealth : nil,
            refreshing: store.isRefreshing)))
        menu.addItem(hostedMenuItem(NativeMenuProviderCardView(
            snapshot: snapshot,
            dashboard: dashboard,
            showAccount: Preferences.shared.showAccountInMenu,
            showMetrics: Preferences.shared.showMenuMetrics,
            showResetTime: Preferences.shared.showResetTime,
            showStatus: Preferences.shared.showServiceStatus,
            quotaPresentation: Preferences.shared.menuQuotaPresentation)))
        menu.addItem(.separator())

        menu.addItem(menuItem(
            title: "Open Detailed Dashboard…",
            action: #selector(openProviderDetailsMenuItem(_:)),
            representedObject: snapshot.id,
            symbol: "chart.bar.xaxis"))
        menu.addItem(menuItem(
            title: "Open Dashboard Popover…",
            action: #selector(openDashboardPopoverMenuItem(_:)),
            representedObject: snapshot.id,
            symbol: "rectangle.portrait.on.rectangle.portrait"))

        if let url = dashboard.dashboardURL {
            menu.addItem(menuItem(
                title: "Usage Dashboard",
                action: #selector(openURLMenuItem(_:)),
                representedObject: url.absoluteString,
                symbol: "arrow.up.right.square"))
        }
        if let url = dashboard.statusURL {
            menu.addItem(menuItem(
                title: "Status Page",
                action: #selector(openURLMenuItem(_:)),
                representedObject: url.absoluteString,
                symbol: "waveform.path.ecg"))
        }
        menu.addItem(menuItem(
            title: dashboard.errorMessage == nil ? "Authentication & Accounts…" : "Fix Authentication…",
            action: #selector(openProviderSettingsMenuItem(_:)),
            representedObject: snapshot.provider,
            symbol: "person.badge.key"))
        menu.addItem(.separator())
        appendCommonActions(to: menu, includeQuit: includeQuit)
    }

    private func appendCommonActions(to menu: NSMenu, includeQuit: Bool) {
        menu.addItem(menuItem(
            title: store.isRefreshing ? "Refreshing…" : "Refresh Now",
            action: #selector(refreshMenuItem),
            keyEquivalent: "r",
            symbol: "arrow.clockwise",
            enabled: !store.isRefreshing))
        menu.addItem(menuItem(
            title: "Settings…",
            action: #selector(openSettingsMenuItem),
            keyEquivalent: ",",
            symbol: "gearshape"))
        menu.addItem(menuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesMenuItem),
            symbol: "arrow.down.circle"))
        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: "Quit CodexBar Monterey",
                action: #selector(quitMenuItem),
                keyEquivalent: "q",
                symbol: "power"))
        }
    }

    private func providerMenuTitle(_ snapshot: ProviderSnapshot) -> String {
        var title = snapshot.displayName
        if Preferences.shared.showAccountInMenu, let account = snapshot.accountDisplayName {
            title += " — \(account)"
        }
        if let used = snapshot.headlineUsedPercent {
            let value = Preferences.shared.menuQuotaPresentation == .used ? used : 100 - used
            let label = snapshot.headlineQuotaLabel.map { "  \($0)" } ?? ""
            title += label + String(format: "  %.0f%%", max(0, min(100, value)))
        }
        if Preferences.shared.showServiceStatus, snapshot.hasVisibleAlert { title += "  ⚠" }
        return title
    }

    private func providerSubtitle(_ snapshot: ProviderSnapshot, dashboard: ProviderDashboard) -> String {
        var parts: [String] = []
        if Preferences.shared.showAccountInMenu, let account = snapshot.accountDisplayName { parts.append(account) }
        if let plan = snapshot.plan, !plan.isEmpty { parts.append(plan) }
        if let source = dashboard.source, !source.isEmpty { parts.append(source) }
        return parts.isEmpty ? dashboard.updatedText : parts.joined(separator: " · ")
    }

    private func menuSubtitle() -> String {
        if store.isRefreshing { return "Refreshing provider usage…" }
        if store.lastError != nil { return "Refresh failed — showing saved data" }
        if let date = store.lastSuccessfulRefresh {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Updated \(formatter.string(from: date)) · \(store.snapshots.count) enabled"
        }
        return "\(store.snapshots.count) enabled providers"
    }

    private func hostedMenuItem<V: View>(_ view: V) -> NSMenuItem {
        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: view.fixedSize(horizontal: false, vertical: true))
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: 310, height: max(1, fitting.height))
        item.view = hosting
        item.isEnabled = false
        return item
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        representedObject: Any? = nil,
        symbol: String? = nil,
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.representedObject = representedObject
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : [.command]
        item.isEnabled = enabled
        if let symbol = symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.image?.isTemplate = true
        }
        return item
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

    @objc private func refreshMenuItem() {
        Task { await refresh() }
    }

    @objc private func openSettingsMenuItem() {
        popover.close()
        detailPopover.close()
        settings.show(selectedProviderID: store.selectedSnapshot?.provider ?? lastMenuProviderID)
    }

    @objc private func openProviderSettingsMenuItem(_ sender: NSMenuItem) {
        guard let providerID = sender.representedObject as? String else { return }
        settings.show(selectedProviderID: providerID)
    }

    @objc private func openProviderDetailsMenuItem(_ sender: NSMenuItem) {
        guard let snapshotID = sender.representedObject as? String,
              let snapshot = store.snapshots.first(where: { $0.id == snapshotID }),
              let button = lastStatusButton
        else { return }
        popover.close()
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self = self, let button = button else { return }
            self.detailPopover.show(snapshot: snapshot, relativeTo: button)
        }
    }

    @objc private func openDashboardPopoverMenuItem(_ sender: NSMenuItem) {
        guard let snapshotID = sender.representedObject as? String,
              let button = lastStatusButton
        else { return }
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self = self, let button = button else { return }
            self.popover.toggle(relativeTo: button, select: snapshotID)
        }
    }

    @objc private func openAllDetailsMenuItem() {
        details.show()
    }

    @objc private func openURLMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdatesMenuItem() {
        updater.checkForUpdates()
    }

    @objc private func quitMenuItem() {
        NSApp.terminate(nil)
    }

    /// End-to-end runtime probe used by local/CI bundle smoke tests. It builds
    /// the same native menus users open, forces the settings hierarchy to load,
    /// and reports structural failures without exposing provider credentials.
    func runtimeSmokeReport() async -> String {
        while store.isRefreshing {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if store.snapshots.isEmpty { await store.refresh() }

        var failures: [String] = []
        let overview = NSMenu(title: "Runtime Smoke Overview")
        populateOverviewMenu(overview)
        let overviewHostedViews = overview.items.compactMap(\.view)
        if overviewHostedViews.count < 2 {
            failures.append("overview hosted rows missing")
        }
        if overviewHostedViews.contains(where: { $0.frame.width < 300 || $0.frame.height < 20 }) {
            failures.append("overview hosted row has invalid size")
        }
        if !store.snapshots.isEmpty,
           !overview.items.contains(where: { $0.title == "Providers" && $0.submenu != nil })
        {
            failures.append("providers submenu missing")
        }

        if let snapshot = store.snapshots.first {
            let providerMenu = NSMenu(title: "Runtime Smoke Provider")
            populateProviderMenu(providerMenu, snapshot: snapshot, includeQuit: true)
            let providerHostedViews = providerMenu.items.compactMap(\.view)
            if providerHostedViews.count < 2 {
                failures.append("provider hosted card missing")
            }
            if providerHostedViews.contains(where: { $0.frame.width < 300 || $0.frame.height < 20 }) {
                failures.append("provider hosted card has invalid size")
            }
            if !providerMenu.items.contains(where: { $0.title == "Authentication & Accounts…" || $0.title == "Fix Authentication…" }) {
                failures.append("authentication action missing")
            }

            let anchor = mergedItem?.button ?? providerItems[snapshot.id]?.button
            if let anchor = anchor {
                detailPopover.show(snapshot: snapshot, relativeTo: anchor)
                if !detailPopover.isShown {
                    failures.append("provider detail popover did not open")
                }
                detailPopover.close()
            } else {
                failures.append("provider detail popover anchor missing")
            }
        }

        if mergedItem?.menu == nil && providerItems.values.allSatisfy({ $0.menu == nil }) {
            failures.append("status item has no native menu")
        }
        if settings.window == nil { failures.append("settings window failed to initialize") }

        let result = failures.isEmpty ? "PASS" : "FAIL: \(failures.joined(separator: "; "))"
        return "\(result) | snapshots=\(store.snapshots.count) overviewItems=\(overview.items.count)"
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
