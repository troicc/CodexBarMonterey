@preconcurrency import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let dashboardStore: DashboardStore

    init(client: CLIClient, updater: UpdaterController, dashboardStore: DashboardStore) {
        self.store = SettingsStore(client: client, updater: updater)
        self.dashboardStore = dashboardStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CodexBar Monterey Settings"
        let frameName = "CodexBarMonterey.SettingsWindow"
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView(store: store, dashboardStore: dashboardStore))
    }

    required init?(coder: NSCoder) { nil }

    func show(
        selectedProviderID: String? = nil,
        selectedTab: SettingsStore.Tab? = nil
    ) {
        if let selectedProviderID = selectedProviderID { store.requestSelection(selectedProviderID) }
        if let selectedTab = selectedTab { store.tab = selectedTab }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !store.isBusy { Task { @MainActor in await store.reloadProviders() } }
    }

    func prepareTokenHistoryVisualQA() {
        let appearance = ProcessInfo.processInfo.environment["CODEXBAR_MONTEREY_VISUAL_QA_APPEARANCE"] == "dark"
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
        // SwiftUI resolves several semantic colors from the application-level
        // appearance. Set both scopes so the source-level snapshot exercises
        // the same light/dark environment as the live window.
        NSApp.appearance = appearance
        window?.appearance = appearance
        window?.setContentSize(NSSize(width: 980, height: 680))
        show(selectedTab: .usageData)
    }

    func tokenHistoryVisualQAReport() -> String {
        guard let window = window, let content = window.contentView else {
            return "FAIL: settings window or content view missing"
        }
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()

        var failures: [String] = []
        if content.bounds.width < 900 || content.bounds.height < 620 {
            failures.append("content viewport is smaller than 900x620")
        }
        let descendants = Self.descendants(of: content)
        let scrollViews = descendants.compactMap { $0 as? NSScrollView }
        let primaryScroll = scrollViews.max {
            ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
        }
        if let primaryScroll = primaryScroll {
            let frame = content.convert(primaryScroll.bounds, from: primaryScroll)
            if frame.width < 600 || frame.height < 500 {
                failures.append("primary history scroll viewport is smaller than 600x500")
            }
        } else {
            failures.append("token history scroll view missing")
        }
        return failures.isEmpty
            ? "PASS | viewport=\(Int(content.bounds.width))x\(Int(content.bounds.height)) scrollViews=\(scrollViews.count)"
            : "FAIL: \(failures.joined(separator: "; "))"
    }

    func writeTokenHistoryVisualQASnapshot(to output: URL) throws {
        guard let window = window, let content = window.contentView else {
            throw NSError(
                domain: "CodexBarMonterey.VisualQA",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Settings window or content view is missing."])
        }
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw NSError(
                domain: "CodexBarMonterey.VisualQA",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate a settings bitmap."])
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "CodexBarMonterey.VisualQA",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode the settings bitmap as PNG."])
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try png.write(to: output, options: .atomic)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case menuBar = "Menu Bar"
        case notifications = "Notifications"
        case usageData = "Usage Data"
        case providers = "Providers"
        case advanced = "Advanced"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .menuBar: return "menubar.rectangle"
            case .notifications: return "bell"
            case .usageData: return "chart.bar"
            case .providers: return "square.grid.2x2"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    @Published var tab: Tab = .providers
    @Published private(set) var providers: [ProviderDescriptor] = []
    @Published var selectedProviderID: String?
    @Published var apiKey = ""
    @Published var credentialLabel = "Default"
    @Published var enterpriseHost = ""
    @Published var workspaceID = ""
    @Published var region = ""
    @Published var revealAPIKey = false
    @Published var providerSearch = ""
    @Published private(set) var status = "Select a provider to configure authentication."
    @Published private(set) var isBusy = false
    @Published private(set) var configuredAccounts: [ConfiguredProviderAccount] = []

    @Published private(set) var refreshMode = Preferences.shared.refreshMode
    @Published private(set) var refreshInterval = Preferences.shared.refreshInterval
    @Published private(set) var refreshOnMenuOpen = Preferences.shared.refreshOnMenuOpen
    @Published private(set) var mergeIcons = Preferences.shared.mergeIcons
    @Published private(set) var menuBarDisplayStyle = Preferences.shared.menuBarDisplayStyle
    @Published private(set) var showAccountInMenu = Preferences.shared.showAccountInMenu
    @Published private(set) var showMenuMetrics = Preferences.shared.showMenuMetrics
    @Published private(set) var showResetTime = Preferences.shared.showResetTime
    @Published private(set) var showServiceStatus = Preferences.shared.showServiceStatus
    @Published private(set) var menuQuotaPresentation = Preferences.shared.menuQuotaPresentation
    @Published private(set) var overviewProviderLimit = Preferences.shared.overviewProviderLimit
    @Published private(set) var notifyOnServiceIncidents = Preferences.shared.notifyOnServiceIncidents
    @Published private(set) var notifyOnRecovery = Preferences.shared.notifyOnRecovery
    @Published private(set) var notifyOnQuotaThreshold = Preferences.shared.notifyOnQuotaThreshold
    @Published private(set) var quotaWarningThreshold = Preferences.shared.quotaWarningThreshold
    @Published private(set) var launchAtLogin = Preferences.shared.launchAtLogin
    @Published private(set) var automaticUpdates = Preferences.shared.automaticUpdates

    private let client: CLIClient
    private let updater: UpdaterController
    private var requestedProviderID: String?
    private var isReloadingProviders = false

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
    }

    var selectedProvider: ProviderDescriptor? {
        guard let selectedProviderID = selectedProviderID else { return nil }
        return providers.first(where: { $0.id == selectedProviderID })
    }

    var selectedAuthenticationProfile: ProviderAuthenticationProfile? {
        guard let provider = selectedProvider else { return nil }
        return ProviderAuthenticationCatalog.profile(for: provider.id)
    }

    var filteredProviders: [ProviderDescriptor] {
        let query = providerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return providers }
        return providers.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var canSaveSelectedConfiguration: Bool {
        guard let profile = selectedAuthenticationProfile, profile.canSaveConfiguration else {
            return false
        }
        if profile.requiresSecret &&
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return false
        }
        if profile.enterpriseHostRequired &&
            enterpriseHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return false
        }
        if profile.workspaceRequired &&
            workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return false
        }
        if profile.storage == .providerFields {
            return !enterpriseHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    func requestSelection(_ providerID: String) {
        requestedProviderID = providerID
        selectedProviderID = providerID
        tab = .providers
    }

    func reloadProviders() async {
        guard !isReloadingProviders else { return }
        isReloadingProviders = true
        isBusy = true
        defer {
            isBusy = false
            isReloadingProviders = false
        }
        do {
            providers = try await client.listProviders()
            let target = requestedProviderID ?? selectedProviderID
            if let target = target, providers.contains(where: { $0.id == target }) {
                selectedProviderID = target
            } else if selectedProviderID == nil {
                selectedProviderID = providers.first?.id
            }
            requestedProviderID = nil
            if let selectedProvider = selectedProvider {
                status = "Selected \(selectedProvider.name) (provider ID: \(selectedProvider.id))."
            } else {
                status = "\(providers.count) providers detected."
            }
            await reloadConfiguredAccounts()
        } catch {
            status = error.localizedDescription
        }
    }

    func select(_ provider: ProviderDescriptor) {
        selectedProviderID = provider.id
        clearCredentialFields()
        let profile = ProviderAuthenticationCatalog.profile(for: provider.id)
        status = "\(profile.title): \(profile.guidance)"
        Task { @MainActor in await reloadConfiguredAccounts() }
    }

    func setEnabled(_ enabled: Bool, provider: ProviderDescriptor) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            do {
                try await client.setProvider(provider.id, enabled: enabled)
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                await reloadProviders()
            } catch {
                status = error.localizedDescription
            }
            isBusy = false
        }
    }

    func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            status = "Clipboard does not contain text."
            return
        }
        apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        status = "API key pasted. Choose Save & Verify."
    }

    func clearAPIKeyField() {
        clearCredentialFields()
        status = "Credential fields cleared."
    }

    private func clearCredentialFields() {
        apiKey = ""
        credentialLabel = "Default"
        enterpriseHost = ""
        workspaceID = ""
        region = ""
        revealAPIKey = false
    }

    func saveAndVerifyAPIKey() {
        guard !isBusy else { return }
        guard let provider = selectedProvider,
              let profile = selectedAuthenticationProfile
        else {
            status = "Select a provider first."
            return
        }
        guard profile.canSaveConfiguration else {
            status = profile.guidance
            return
        }

        let input = ProviderCredentialInput(
            secret: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            accountLabel: credentialLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            enterpriseHost: enterpriseHost.trimmingCharacters(in: .whitespacesAndNewlines),
            workspaceID: workspaceID.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines))

        isBusy = true
        Task { @MainActor in
            let receipt: CredentialSaveReceipt
            do {
                status = "Saving and verifying \(provider.name)…"
                receipt = try await client.saveCredential(
                    input,
                    provider: provider.id,
                    profile: profile)
            } catch {
                status = "Save failed: \(error.localizedDescription)"
                isBusy = false
                return
            }

            NotificationCenter.default.post(
                name: .providerConfigurationChanged,
                object: provider.id)
            clearCredentialFields()
            await reloadProviders()
            status = "\(provider.name) configuration saved and verified in \(receipt.configURL.path)."
            isBusy = false
        }
    }

    func refreshBrowserSession() {
        guard !isBusy else { return }
        guard let provider = selectedProvider else { return }
        isBusy = true
        Task { @MainActor in
            do {
                let result = try await client.refreshBrowserSession(provider: provider.id)
                status = result.isEmpty ? "Browser session refreshed for \(provider.name)." : result
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
            } catch {
                status = error.localizedDescription
            }
            isBusy = false
        }
    }

    func clearBrowserSession() {
        guard !isBusy else { return }
        guard let provider = selectedProvider else { return }
        isBusy = true
        Task { @MainActor in
            do {
                let result = try await client.clearBrowserSession(provider: provider.id)
                status = result.isEmpty ? "Browser cache cleared for \(provider.name)." : result
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
            } catch {
                status = error.localizedDescription
            }
            isBusy = false
        }
    }

    func openProviderDocs() {
        guard let provider = selectedProvider else { return }
        NSWorkspace.shared.open(ProviderCatalog.documentationURL(for: provider.id))
    }

    func openConfig() {
        Task { @MainActor in
            do {
                let target = try await client.configFileURL()
                NSWorkspace.shared.open(target)
            } catch {
                status = "Could not open config file: \(error.localizedDescription)"
            }
        }
    }

    func validateConfig() {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            do { status = try await client.validateConfig() }
            catch { status = error.localizedDescription }
            isBusy = false
        }
    }

    func openLogs() {
        let candidates = [
            URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
            URL(fileURLWithPath: "/Applications/Utilities/Console.app"),
        ]
        guard let console = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            status = "Console.app could not be found."
            return
        }
        NSWorkspace.shared.open(console)
        status = "Opened Console. Search for CodexBarMonterey to view diagnostics."
    }

    func checkUpdates() { updater.checkForUpdates() }

    func reloadConfiguredAccounts() async {
        guard let provider = selectedProvider else {
            configuredAccounts = []
            return
        }
        do {
            configuredAccounts = try await client.configuredAccounts(provider: provider.id)
        } catch {
            configuredAccounts = []
            status = "Could not read configured accounts: \(error.localizedDescription)"
        }
    }

    func activateConfiguredAccount(_ account: ConfiguredProviderAccount) {
        guard !isBusy,
              let provider = selectedProvider,
              let profile = selectedAuthenticationProfile
        else { return }
        isBusy = true
        Task { @MainActor in
            do {
                status = "Switching \(provider.name) to \(account.label)…"
                try await client.activateConfiguredAccount(
                    provider: provider.id,
                    accountID: account.id,
                    profile: profile)
                await reloadConfiguredAccounts()
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                status = "\(account.label) is now the active \(provider.name) account."
            } catch {
                status = "Account switch failed: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func removeConfiguredAccount(_ account: ConfiguredProviderAccount) {
        guard !isBusy, let provider = selectedProvider else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(account.label)?"
        alert.informativeText = "This removes the saved token from the CodexBar configuration. Other accounts are preserved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isBusy = true
        Task { @MainActor in
            do {
                try await client.removeConfiguredAccount(provider: provider.id, accountID: account.id)
                await reloadConfiguredAccounts()
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                status = "Removed \(account.label) from \(provider.name)."
            } catch {
                status = "Account removal failed: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    func setRefreshMode(_ value: RefreshMode) {
        refreshMode = value
        Preferences.shared.refreshMode = value
        postPreferencesChanged()
    }

    func setRefreshInterval(_ value: TimeInterval) {
        refreshInterval = value
        Preferences.shared.refreshInterval = value
        postPreferencesChanged()
    }

    func setRefreshOnMenuOpen(_ value: Bool) {
        refreshOnMenuOpen = value
        Preferences.shared.refreshOnMenuOpen = value
        postPreferencesChanged()
    }

    func setMergeIcons(_ value: Bool) {
        mergeIcons = value
        Preferences.shared.mergeIcons = value
        postPreferencesChanged()
    }

    func setMenuBarDisplayStyle(_ value: MenuBarDisplayStyle) {
        menuBarDisplayStyle = value
        Preferences.shared.menuBarDisplayStyle = value
        postPreferencesChanged()
    }

    func setShowAccountInMenu(_ value: Bool) {
        showAccountInMenu = value
        Preferences.shared.showAccountInMenu = value
        postPreferencesChanged()
    }

    func setShowMenuMetrics(_ value: Bool) {
        showMenuMetrics = value
        Preferences.shared.showMenuMetrics = value
        postPreferencesChanged()
    }

    func setShowResetTime(_ value: Bool) {
        showResetTime = value
        Preferences.shared.showResetTime = value
        postPreferencesChanged()
    }

    func setShowServiceStatus(_ value: Bool) {
        showServiceStatus = value
        Preferences.shared.showServiceStatus = value
        postPreferencesChanged()
    }

    func setMenuQuotaPresentation(_ value: MenuQuotaPresentation) {
        menuQuotaPresentation = value
        Preferences.shared.menuQuotaPresentation = value
        postPreferencesChanged()
    }

    func setOverviewProviderLimit(_ value: Int) {
        overviewProviderLimit = value
        Preferences.shared.overviewProviderLimit = value
        postPreferencesChanged()
    }

    func setNotifyOnServiceIncidents(_ value: Bool) {
        notifyOnServiceIncidents = value
        Preferences.shared.notifyOnServiceIncidents = value
        if value { ProviderAlertController.requestAuthorization() }
        postPreferencesChanged()
    }

    func setNotifyOnRecovery(_ value: Bool) {
        notifyOnRecovery = value
        Preferences.shared.notifyOnRecovery = value
        postPreferencesChanged()
    }

    func setNotifyOnQuotaThreshold(_ value: Bool) {
        notifyOnQuotaThreshold = value
        Preferences.shared.notifyOnQuotaThreshold = value
        if value { ProviderAlertController.requestAuthorization() }
        postPreferencesChanged()
    }

    func setQuotaWarningThreshold(_ value: Double) {
        quotaWarningThreshold = value
        Preferences.shared.quotaWarningThreshold = value
        postPreferencesChanged()
    }

    func setLaunchAtLogin(_ value: Bool) {
        launchAtLogin = value
        Preferences.shared.launchAtLogin = value
    }

    func setAutomaticUpdates(_ value: Bool) {
        automaticUpdates = value
        Preferences.shared.automaticUpdates = value
        updater.setAutomatic(value)
    }

    private func postPreferencesChanged() {
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }
}

private struct SettingsRootView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var dashboardStore: DashboardStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CodexBar Monterey")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                ForEach(SettingsStore.Tab.allCases) { tab in
                    Button(action: { store.tab = tab }) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.symbol)
                                .frame(width: 18)
                            Text(tab.rawValue)
                            Spacer()
                        }
                        .font(.system(size: 13, weight: store.tab == tab ? .semibold : .regular))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(store.tab == tab ? Color.accentColor.opacity(0.18) : Color.clear))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 190)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))

            Divider()

            Group {
                switch store.tab {
                case .general: GeneralSettingsView(store: store)
                case .menuBar: MenuBarSettingsView(store: store)
                case .notifications: NotificationSettingsView(store: store)
                case .usageData: TokenHistorySettingsView(dashboardStore: dashboardStore)
                case .providers: ProviderSettingsView(store: store, dashboardStore: dashboardStore)
                case .advanced: AdvancedSettingsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if !store.isBusy { await store.reloadProviders() }
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    private let intervals: [(String, TimeInterval)] = [
        ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300), ("15 minutes", 900), ("30 minutes", 1800),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageTitle(
                    title: "General",
                    subtitle: "Refresh behavior and application lifecycle")
                GroupBox(label: Text("Refresh").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: Binding(
                            get: { store.refreshMode },
                            set: { store.setRefreshMode($0) }))
                        {
                            ForEach(RefreshMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        if store.refreshMode == .fixed {
                            Picker("Interval", selection: Binding(
                                get: { store.refreshInterval },
                                set: { store.setRefreshInterval($0) }))
                            {
                                ForEach(Array(intervals.enumerated()), id: \.offset) { _, entry in
                                    Text(entry.0).tag(entry.1)
                                }
                            }
                        }
                        Toggle(
                            "Refresh when the status menu opens",
                            isOn: Binding(get: { store.refreshOnMenuOpen }, set: { store.setRefreshOnMenuOpen($0) }))
                        if store.refreshMode == .adaptive {
                            Text("Adaptive refresh uses 2 minutes after menu activity, 5 minutes while warm, 15 minutes while idle, and 30 minutes in Low Power Mode.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                }
                GroupBox(label: Text("Application").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                        Toggle("Automatically download updates", isOn: Binding(get: { store.automaticUpdates }, set: { store.setAutomaticUpdates($0) }))
                    }
                    .padding(12)
                }
            }
            .padding(28)
        }
    }
}

private struct MenuBarSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageTitle(
                    title: "Menu Bar",
                    subtitle: "Choose what appears in the status item and native menu")
                GroupBox(label: Text("Status item").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Display", selection: Binding(
                            get: { store.menuBarDisplayStyle },
                            set: { store.setMenuBarDisplayStyle($0) }))
                        {
                            ForEach(MenuBarDisplayStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        Toggle("Merge provider icons", isOn: Binding(get: { store.mergeIcons }, set: { store.setMergeIcons($0) }))
                    }
                    .padding(12)
                }
                GroupBox(label: Text("Native menu content").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show account names", isOn: Binding(get: { store.showAccountInMenu }, set: { store.setShowAccountInMenu($0) }))
                        Toggle("Show summary metrics", isOn: Binding(get: { store.showMenuMetrics }, set: { store.setShowMenuMetrics($0) }))
                        Toggle("Show reset time and pace", isOn: Binding(get: { store.showResetTime }, set: { store.setShowResetTime($0) }))
                        Toggle("Show provider service status", isOn: Binding(get: { store.showServiceStatus }, set: { store.setShowServiceStatus($0) }))
                        Picker("Quota values", selection: Binding(
                            get: { store.menuQuotaPresentation },
                            set: { store.setMenuQuotaPresentation($0) }))
                        {
                            ForEach(MenuQuotaPresentation.allCases) { presentation in
                                Text(presentation.title).tag(presentation)
                            }
                        }
                        Picker("Overview rows", selection: Binding(
                            get: { store.overviewProviderLimit },
                            set: { store.setOverviewProviderLimit($0) }))
                        {
                            Text("3 providers").tag(3)
                            Text("6 providers").tag(6)
                            Text("9 providers").tag(9)
                            Text("12 providers").tag(12)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(28)
        }
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageTitle(
                    title: "Notifications",
                    subtitle: "Receive transition-based alerts without repeated notification noise")
                GroupBox(label: Text("Provider status").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Notify when a provider becomes unavailable or degraded",
                            isOn: Binding(
                                get: { store.notifyOnServiceIncidents },
                                set: { store.setNotifyOnServiceIncidents($0) }))
                        Toggle(
                            "Notify when the provider recovers",
                            isOn: Binding(get: { store.notifyOnRecovery }, set: { store.setNotifyOnRecovery($0) }))
                            .disabled(!store.notifyOnServiceIncidents)
                    }
                    .padding(12)
                }
                GroupBox(label: Text("Quota warnings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Notify when usage crosses the warning threshold",
                            isOn: Binding(
                                get: { store.notifyOnQuotaThreshold },
                                set: { store.setNotifyOnQuotaThreshold($0) }))
                        HStack {
                            Text("Warning threshold")
                            Slider(
                                value: Binding(
                                    get: { store.quotaWarningThreshold },
                                    set: { store.setQuotaWarningThreshold($0) }),
                                in: 50 ... 100,
                                step: 5)
                            Text(String(format: "%.0f%%", store.quotaWarningThreshold))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 42, alignment: .trailing)
                        }
                        .disabled(!store.notifyOnQuotaThreshold)
                        Text("Alerts are sent only when a refreshed value crosses the threshold. The first refresh after launch establishes a baseline.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                }
            }
            .padding(28)
        }
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var dashboardStore: DashboardStore

    var body: some View {
        HStack(spacing: 0) {
            providerList
                .frame(width: 340)
                .disabled(store.isBusy)
            Divider()
            configurationPane
        }
    }

    private var providerList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Providers").font(.system(size: 17, weight: .bold))
                Spacer()
                Button(action: { Task { @MainActor in await store.reloadProviders() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            TextField("Search providers", text: $store.providerSearch)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.filteredProviders) { provider in
                        ProviderSettingsRow(
                            provider: provider,
                            selected: store.selectedProviderID == provider.id,
                            select: { store.select(provider) },
                            toggle: { store.setEnabled($0, provider: provider) })
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var configurationPane: some View {
        if let provider = store.selectedProvider {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(ProviderBrand.color(for: provider.id).opacity(0.18))
                            Image(systemName: ProviderBrand.symbol(for: provider.id))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(ProviderBrand.color(for: provider.id))
                        }
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.name).font(.system(size: 22, weight: .bold))
                            Text("Provider ID: \(provider.id)").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }

                    let profile = ProviderAuthenticationCatalog.profile(for: provider.id)
                    let connectedSnapshots = dashboardStore.snapshots.filter { $0.provider == provider.id }

                    GroupBox(label: Text("Connection & service").font(.headline)) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Label(profile.methodTitle, systemImage: profile.methodSymbol)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text(provider.enabled ? "Enabled" : "Disabled")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(provider.enabled ? .green : .secondary)
                            }
                            if connectedSnapshots.isEmpty {
                                Text(provider.enabled
                                    ? "No account snapshot is available yet. Refresh after configuring authentication."
                                    : "Enable this provider to fetch account and quota information.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(connectedSnapshots) { snapshot in
                                    ProviderConnectionRow(snapshot: snapshot)
                                }
                            }
                        }
                        .padding(10)
                    }

                    GroupBox(label: Text(profile.title).font(.headline)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(profile.guidance)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            if profile.canSaveConfiguration {
                                if profile.requiresSecret {
                                    Text(profile.secretLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                    HStack(spacing: 8) {
                                        Group {
                                            if store.revealAPIKey {
                                                TextField(profile.secretPlaceholder, text: $store.apiKey)
                                            } else {
                                                SecureField(profile.secretPlaceholder, text: $store.apiKey)
                                            }
                                        }
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        Button(action: { store.pasteAPIKey() }) {
                                            Label("Paste", systemImage: "doc.on.clipboard")
                                        }
                                        Button(action: { store.revealAPIKey.toggle() }) {
                                            Image(systemName: store.revealAPIKey ? "eye.slash" : "eye")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }

                                if profile.accountLabelVisible {
                                    TextField("Account label", text: $store.credentialLabel)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }

                                if let label = profile.enterpriseHostLabel {
                                    TextField(label, text: $store.enterpriseHost)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }

                                if let label = profile.workspaceLabel {
                                    TextField(label, text: $store.workspaceID)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }

                                if let label = profile.regionLabel {
                                    TextField(
                                        profile.regionPlaceholder.map { "\(label): \($0)" } ?? label,
                                        text: $store.region)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }

                                HStack {
                                    Button("Save & Verify", action: { store.saveAndVerifyAPIKey() })
                                        .keyboardShortcut(.defaultAction)
                                        .disabled(!store.canSaveSelectedConfiguration || store.isBusy)
                                    Button("Clear fields", action: { store.clearAPIKeyField() })
                                        .disabled(store.isBusy)
                                    Spacer()
                                }
                            } else {
                                Text("This provider does not accept a generic config API key. Use the provider login, CLI, OAuth, browser, or local source described above.")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .padding(10)
                    }
                    .disabled(store.isBusy)

                    if profile.storage == .tokenAccount {
                        GroupBox(label: Text("Saved token accounts").font(.headline)) {
                            VStack(alignment: .leading, spacing: 9) {
                                if store.configuredAccounts.isEmpty {
                                    Text("No token accounts are saved. Enter a label and API key above to add one.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(store.configuredAccounts) { account in
                                        HStack(spacing: 9) {
                                            Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(account.isActive ? .green : .secondary)
                                            Text(account.label)
                                                .font(.system(size: 12, weight: account.isActive ? .semibold : .regular))
                                            if account.isActive {
                                                Text("Active")
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            if !account.isActive {
                                                Button("Use", action: { store.activateConfiguredAccount(account) })
                                            }
                                            Button("Remove", action: { store.removeConfiguredAccount(account) })
                                                .foregroundColor(.red)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .padding(10)
                            .disabled(store.isBusy)
                        }
                    }

                    GroupBox(label: Text("Provider tools").font(.headline)) {
                        HStack(spacing: 10) {
                            if profile.supportsBrowserTools {
                                Button("Refresh browser session", action: { store.refreshBrowserSession() })
                                Button("Clear browser cache", action: { store.clearBrowserSession() })
                            }
                            Button("Provider docs", action: { store.openProviderDocs() })
                            Spacer()
                        }
                        .padding(10)
                        .disabled(store.isBusy)
                    }

                    GroupBox(label: Text("Status").font(.headline)) {
                        HStack(alignment: .top, spacing: 8) {
                            if store.isBusy { ProgressView().scaleEffect(0.7) }
                            Text(store.status)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                    }
                }
                .padding(24)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.left").font(.system(size: 32)).foregroundColor(.secondary)
                Text("Select a provider").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SettingsPageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

private struct ProviderConnectionRow: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.accountDisplayName ?? snapshot.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let percent = snapshot.maximumUsedPercent {
                Text(String(format: "%.0f%% used", percent))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        if let error = snapshot.error?.message { return error }
        if snapshot.serviceHealth.isIncident, let status = snapshot.status { return status.displayText }
        let parts = [snapshot.source, snapshot.planDisplayName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }

    private var connectionColor: Color {
        if snapshot.error != nil { return .red }
        switch snapshot.serviceHealth {
        case .unknown: return .secondary
        case .operational: return .green
        case .degraded: return .orange
        case .outage: return .red
        }
    }
}

private struct ProviderSettingsRow: View {
    let provider: ProviderDescriptor
    let selected: Bool
    let select: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { provider.enabled }, set: toggle))
                .labelsHidden()
            Button(action: select) {
                HStack(spacing: 9) {
                    Image(systemName: ProviderBrand.symbol(for: provider.id))
                        .foregroundColor(ProviderBrand.color(for: provider.id))
                        .frame(width: 22)
                    Text(provider.name)
                        .lineLimit(1)
                    Spacer()
                    if selected { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.18) : Color.clear))
    }
}

struct TokenHistorySettingsView: View {
    @ObservedObject var dashboardStore: DashboardStore
    @State private var selectedAccountID = ""
    @State private var range: TokenHistoryRange = .thirtyDays
    @State private var exportStatus: String?

    init(dashboardStore: DashboardStore, selectedAccountID: String = "") {
        self.dashboardStore = dashboardStore
        _selectedAccountID = State(initialValue: selectedAccountID)
    }

    private var accountID: String? {
        selectedAccountID.isEmpty ? nil : selectedAccountID
    }

    private var report: TokenHistoryReport {
        // Reading the revision makes this derived report refresh immediately
        // when a provider poll adds or corrects dated token buckets.
        _ = dashboardStore.tokenHistoryRevision
        return dashboardStore.tokenHistoryReport(accountID: accountID, range: range)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageTitle(
                    title: "Usage Data",
                    subtitle: "Long-term token history, every available token component, and portable exports")

                HStack(spacing: 14) {
                    Picker("Account", selection: $selectedAccountID) {
                        Text("All providers & accounts").tag("")
                        ForEach(dashboardStore.tokenHistoryAccounts) { account in
                            Text(account.displayName).tag(account.id)
                        }
                    }
                    .frame(maxWidth: 360)

                    Picker("Range", selection: $range) {
                        ForEach(TokenHistoryRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: 360)
                }

                Text("Claude and Codex show local model usage, not official quota consumption or invoices. Other Claude Code models are kept separately and excluded from the combined total to avoid overlap with provider API data. Mixed days without model token counts remain unattributed. Token components appear only when complete.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if report.recordCount == 0 {
                    TokenHistoryEmptyState()
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                        spacing: 10)
                    {
                        TokenHistoryStatCard(
                            title: "\(range.title) tokens",
                            value: tokenHistoryCompactNumber(report.totalTokens),
                            detail: "\(report.recordCount) dated buckets")
                        TokenHistoryStatCard(
                            title: "Today",
                            value: tokenHistoryCompactNumber(report.todayTokens),
                            detail: "Local calendar day")
                        TokenHistoryStatCard(
                            title: "30 days",
                            value: tokenHistoryCompactNumber(report.last30DaysTokens),
                            detail: tokenHistoryCoverageDetail(report))
                        TokenHistoryStatCard(
                            title: "All time",
                            value: tokenHistoryCompactNumber(report.allTimeTokens),
                            detail: "Never auto-pruned")
                    }

                    HStack(alignment: .top, spacing: 12) {
                        if !report.modelTotals.isEmpty {
                            TokenHistoryBreakdownBox(
                                title: "Models",
                                rows: report.modelTotals)
                        }
                        if report.providerTotals.count > 1 {
                            TokenHistoryBreakdownBox(
                                title: "Providers",
                                rows: report.providerTotals)
                        }
                    }

                    GroupBox(label: Text("Token volume · \(range.title)").font(.headline)) {
                        TokenHistoryBarChart(points: report.chart)
                            .padding(12)
                    }

                    if report.components.hasData {
                        GroupBox(label: Text("Token components · \(range.title)").font(.headline)) {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                spacing: 10)
                            {
                                TokenHistoryComponentCell(title: "Input", value: report.components.input)
                                TokenHistoryComponentCell(title: "Output", value: report.components.output)
                                TokenHistoryComponentCell(title: "Cache read", value: report.components.cacheRead)
                                TokenHistoryComponentCell(title: "Cache creation", value: report.components.cacheCreation)
                            }
                            .padding(12)
                        }
                    }


                }

                GroupBox(label: Text("Retention & export").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dated token buckets are merged by provider, account, time, and model in Application Support. Existing buckets are updated in place and are never automatically deleted. Quota percentages are stored separately and are not counted as tokens.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(dashboardStore.tokenHistoryStorageURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        HStack(spacing: 10) {
                            Button("Export visible CSV…", action: exportVisibleCSV)
                            Button("Export full JSON…", action: exportFullJSON)
                            Button("Show data file", action: revealDataFile)
                            Spacer()
                        }

                        if let persistenceError = dashboardStore.tokenHistoryPersistenceError {
                            Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let exportStatus = exportStatus {
                            Text(exportStatus)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(28)
        }
    }

    private func exportVisibleCSV() {
        let csv = dashboardStore.tokenHistoryCSV(accountID: accountID, range: range)
        save(
            data: Data(csv.utf8),
            suggestedName: "codexbar-token-history-\(range.rawValue).csv")
    }

    private func exportFullJSON() {
        do {
            let data = try dashboardStore.tokenHistoryJSON(accountID: nil, range: nil)
            save(
                data: data,
                suggestedName: "codexbar-token-history-full.json")
        } catch {
            exportStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func save(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try data.write(to: destination, options: .atomic)
            exportStatus = "Exported \(destination.lastPathComponent)"
        } catch {
            exportStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func revealDataFile() {
        let fileURL = dashboardStore.tokenHistoryStorageURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
        }
    }
}

private struct TokenHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No dated token history in this range")
                .font(.system(size: 15, weight: .semibold))
            Text("Refresh a provider that exposes dated token usage. Codex and Claude import their current daily history; z.ai imports its rolling hourly model data and keeps it permanently from then on.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
    }
}

private struct TokenHistoryStatCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

private struct TokenHistoryComponentCell: View {
    let title: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value.map(tokenHistoryCompactNumber) ?? "—")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenHistoryBreakdownBox: View {
    let title: String
    let rows: [TokenHistoryNamedTotal]

    var body: some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(tokenHistoryCompactNumber(row.tokens))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .help(String(format: "%.0f tokens", row.tokens))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TokenHistoryBarChart: View {
    let points: [TokenHistoryChartPoint]

    private var maximum: Double {
        max(1, points.map(\.tokens).max() ?? 1)
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<4) { index in
                            if index > 0 { Spacer() }
                            Divider().opacity(0.45)
                        }
                    }
                    HStack(alignment: .bottom, spacing: points.count > 60 ? 1 : 3) {
                        ForEach(points) { point in
                            TokenHistoryBar(point: point, maximum: maximum,
                                height: geometry.size.height, dense: points.count > 60)
                        }
                    }
                }
            }
            .frame(height: 176)

            HStack {
                Text(points.first?.label ?? "")
                Spacer()
                if points.count > 2 { Text(points[points.count / 2].label) }
                Spacer()
                Text(points.last?.label ?? "")
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
    }
}

private struct TokenHistoryBar: View {
    let point: TokenHistoryChartPoint
    let maximum: Double
    let height: CGFloat
    let dense: Bool

    private var valueText: String {
        point.hasRecords ? "\(tokenHistoryCompactNumber(point.tokens)) tokens" : "No recorded data"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: dense ? 1 : 2)
            .fill(Color.accentColor.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: point.tokens > 0 ? max(2, CGFloat(point.tokens / maximum) * height) : 0)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .accessibilityLabel(point.label)
            .accessibilityValue(valueText)
            .help("\(point.label): \(valueText)")
    }
}

private func tokenHistoryCoverageDetail(_ report: TokenHistoryReport) -> String {
    guard let first = report.firstRecordedAt else { return "No local coverage" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d, yyyy"
    return "Since \(formatter.string(from: first))"
}

private func tokenHistoryCompactNumber(_ value: Double) -> String {
    guard value.isFinite else { return "—" }
    let absolute = abs(value)
    let divisor: Double
    let suffix: String
    switch absolute {
    case 1_000_000_000...:
        divisor = 1_000_000_000
        suffix = "B"
    case 1_000_000...:
        divisor = 1_000_000
        suffix = "M"
    case 1_000...:
        divisor = 1_000
        suffix = "K"
    default:
        return String(format: "%.0f", value)
    }
    let scaled = value / divisor
    return String(format: scaled >= 100 ? "%.0f%@" : (scaled >= 10 ? "%.1f%@" : "%.2f%@"), scaled, suffix)
}

private struct AdvancedSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Check for updates", action: { store.checkUpdates() })
            Button("Validate provider configuration", action: { store.validateConfig() })
            Button("Open config file", action: { store.openConfig() })
            Button("Open Console logs", action: { store.openLogs() })
            GroupBox(label: Text("Command output")) {
                ScrollView {
                    Text(store.status)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 200)
            }
            Spacer()
        }
        .padding(28)
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("CodexBarMonterey.preferencesChanged")
    static let providerConfigurationChanged = Notification.Name("CodexBarMonterey.providerConfigurationChanged")
}
