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
        window.center()
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
        Task { await store.reloadProviders() }
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

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
    }

    var selectedProvider: ProviderDescriptor? {
        guard let selectedProviderID = selectedProviderID else { return nil }
        return providers.first(where: { $0.id == selectedProviderID })
    }

    func requestSelection(_ providerID: String) {
        requestedProviderID = providerID
        selectedProviderID = providerID
        tab = .providers
    }

    func reloadProviders() async {
        isBusy = true
        defer { isBusy = false }
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
        apiKey = ""
        status = "Selected \(provider.name) (provider ID: \(provider.id))."
    }

    func setEnabled(_ enabled: Bool, provider: ProviderDescriptor) {
        Task {
            isBusy = true
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
        apiKey = ""
        status = "API key field cleared."
    }

    func saveAndVerifyAPIKey() {
        guard let provider = selectedProvider else {
            status = "Select a provider first."
            return
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            status = "Paste or type an API key first."
            return
        }
        Task {
            isBusy = true
            status = "Saving API key for \(provider.name)…"
            defer { isBusy = false }
            do {
                try await client.setAPIKey(key, provider: provider.id)
                status = "API key saved. Verifying \(provider.name)…"
                let result = try await client.probeAPIProvider(provider.id)
                apiKey = ""
                status = result.isEmpty ? "\(provider.name) API key saved and verified." : result
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                await reloadProviders()
            } catch {
                status = "Saved, but verification failed: \(error.localizedDescription)"
            }
        }
    }

    func refreshBrowserSession() {
        guard let provider = selectedProvider else { return }
        Task {
            isBusy = true
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
        guard let provider = selectedProvider else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let result = try await client.clearBrowserSession(provider: provider.id)
                status = result.isEmpty ? "Browser cache cleared for \(provider.name)." : result
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdg = home.appendingPathComponent(".config/codexbar/config.json")
        let legacy = home.appendingPathComponent(".codexbar/config.json")
        let target: URL
        if FileManager.default.fileExists(atPath: xdg.path) {
            target = xdg
        } else if FileManager.default.fileExists(atPath: legacy.path) {
            target = legacy
        } else {
            target = xdg
            do {
                try FileManager.default.createDirectory(at: xdg.deletingLastPathComponent(), withIntermediateDirectories: true)
                let config = """
                {
                  "version": 1,
                  "hooks": null,
                  "providers": []
                }
                """
                try Data((config + "\n").utf8).write(to: target, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            } catch {
                status = "Could not create config file: \(error.localizedDescription)"
                return
            }
        }
        NSWorkspace.shared.open(target)
    }

    func validateConfig() {
        Task {
            isBusy = true
            defer { isBusy = false }
            do { status = try await client.validateConfig() }
            catch { status = error.localizedDescription }
        }
    }

    func openLogs() {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CodexBarMonterey")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logs)
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
        .task { await store.reloadProviders() }
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

                    GroupBox(label: Text("API authentication").font(.headline)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Paste the provider token below. The value is sent to the bundled upstream CLI over stdin and is never added to shell history.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Group {
                                    if store.revealAPIKey {
                                        TextField("Paste API key or token", text: $store.apiKey)
                                    } else {
                                        SecureField("Paste API key or token", text: $store.apiKey)
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
                            HStack {
                                Button("Save & Verify", action: store.saveAndVerifyAPIKey)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
                                Button("Clear field", action: store.clearAPIKeyField)
                                Spacer()
                            }
                        }
                        .padding(10)
                    }

                    GroupBox(label: Text("Browser and provider tools").font(.headline)) {
                        HStack(spacing: 10) {
                            Button("Refresh browser session", action: store.refreshBrowserSession)
                            Button("Clear browser cache", action: store.clearBrowserSession)
                            Button("Provider docs", action: store.openProviderDocs)
                            Spacer()
                        }
                        .padding(10)
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
            Button("Open logs folder", action: store.openLogs)
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
