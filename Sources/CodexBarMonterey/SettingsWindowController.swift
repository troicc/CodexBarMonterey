@preconcurrency import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore

    init(client: CLIClient, updater: UpdaterController) {
        self.store = SettingsStore(client: client, updater: updater)
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
        window.contentViewController = NSHostingController(rootView: SettingsRootView(store: store))
    }

    required init?(coder: NSCoder) { nil }

    func show(selectedProviderID: String? = nil) {
        if let selectedProviderID = selectedProviderID { store.requestSelection(selectedProviderID) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !store.isBusy { Task { await store.reloadProviders() } }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case providers = "Providers"
        case advanced = "Advanced"
        var id: String { rawValue }
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
    @Published private(set) var status = "Select a provider to configure authentication."
    @Published private(set) var isBusy = false

    @Published private(set) var refreshInterval = Preferences.shared.refreshInterval
    @Published private(set) var mergeIcons = Preferences.shared.mergeIcons
    @Published private(set) var showPercentage = Preferences.shared.showPercentage
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
        } catch {
            status = error.localizedDescription
        }
    }

    func select(_ provider: ProviderDescriptor) {
        selectedProviderID = provider.id
        clearCredentialFields()
        let profile = ProviderAuthenticationCatalog.profile(for: provider.id)
        status = "\(profile.title): \(profile.guidance)"
    }

    func setEnabled(_ enabled: Bool, provider: ProviderDescriptor) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await client.setProvider(provider.id, enabled: enabled)
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                await reloadProviders()
            } catch {
                status = error.localizedDescription
            }
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
        Task {
            defer { isBusy = false }

            let receipt: CredentialSaveReceipt
            do {
                status = "Saving and verifying \(provider.name)…"
                receipt = try await client.saveCredential(
                    input,
                    provider: provider.id,
                    profile: profile)
            } catch {
                status = "Save failed: \(error.localizedDescription)"
                return
            }

            NotificationCenter.default.post(
                name: .providerConfigurationChanged,
                object: provider.id)
            clearCredentialFields()
            await reloadProviders()
            status = "\(provider.name) configuration saved and verified in \(receipt.configURL.path)."
        }
    }

    func refreshBrowserSession() {
        guard !isBusy else { return }
        guard let provider = selectedProvider else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await client.refreshBrowserSession(provider: provider.id)
                status = result.isEmpty ? "Browser session refreshed for \(provider.name)." : result
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func clearBrowserSession() {
        guard !isBusy else { return }
        guard let provider = selectedProvider else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await client.clearBrowserSession(provider: provider.id)
                status = result.isEmpty ? "Browser cache cleared for \(provider.name)." : result
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func openProviderDocs() {
        guard let provider = selectedProvider else { return }
        NSWorkspace.shared.open(ProviderCatalog.documentationURL(for: provider.id))
    }

    func openConfig() {
        Task {
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
        Task {
            defer { isBusy = false }
            do { status = try await client.validateConfig() }
            catch { status = error.localizedDescription }
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

    func setRefreshInterval(_ value: TimeInterval) {
        refreshInterval = value
        Preferences.shared.refreshInterval = value
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    func setMergeIcons(_ value: Bool) {
        mergeIcons = value
        Preferences.shared.mergeIcons = value
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    func setShowPercentage(_ value: Bool) {
        showPercentage = value
        Preferences.shared.showPercentage = value
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
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
}

private struct SettingsRootView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $store.tab) {
                ForEach(SettingsStore.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 430)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch store.tab {
                case .general: GeneralSettingsView(store: store)
                case .providers: ProviderSettingsView(store: store)
                case .advanced: AdvancedSettingsView(store: store)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
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
        Form {
            Picker("Refresh interval", selection: Binding(
                get: { store.refreshInterval },
                set: store.setRefreshInterval))
            {
                ForEach(Array(intervals.enumerated()), id: \.offset) { _, entry in
                    Text(entry.0).tag(entry.1)
                }
            }
            Toggle("Merge provider icons", isOn: Binding(get: { store.mergeIcons }, set: store.setMergeIcons))
            Toggle("Show highest used percentage", isOn: Binding(get: { store.showPercentage }, set: store.setShowPercentage))
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: store.setLaunchAtLogin))
            Toggle("Automatically download updates", isOn: Binding(get: { store.automaticUpdates }, set: store.setAutomaticUpdates))
        }
        .padding(28)
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var store: SettingsStore

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
                Button(action: { Task { await store.reloadProviders() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.providers) { provider in
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
                                        Button(action: store.pasteAPIKey) {
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
                                    Button("Save & Verify", action: store.saveAndVerifyAPIKey)
                                        .keyboardShortcut(.defaultAction)
                                        .disabled(!store.canSaveSelectedConfiguration || store.isBusy)
                                    Button("Clear fields", action: store.clearAPIKeyField)
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

                    GroupBox(label: Text("Provider tools").font(.headline)) {
                        HStack(spacing: 10) {
                            if profile.supportsBrowserTools {
                                Button("Refresh browser session", action: store.refreshBrowserSession)
                                Button("Clear browser cache", action: store.clearBrowserSession)
                            }
                            Button("Provider docs", action: store.openProviderDocs)
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

private struct AdvancedSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Check for updates", action: store.checkUpdates)
            Button("Validate provider configuration", action: store.validateConfig)
            Button("Open config file", action: store.openConfig)
            Button("Open Console logs", action: store.openLogs)
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
