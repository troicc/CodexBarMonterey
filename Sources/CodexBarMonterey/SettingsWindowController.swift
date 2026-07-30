@preconcurrency import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let client: CLIClient
    private let updater: UpdaterController
    private let table = NSTableView()
    private var providers: [ProviderDescriptor] = []
    private let statusLabel = NSTextField(labelWithString: "")
    private let setAPIKeyButton = NSButton(title: "Set API key…", target: nil, action: nil)

    init(client: CLIClient, updater: UpdaterController) {
        self.client = client
        self.updater = updater
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "CodexBar Monterey Settings"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await reloadProviders() }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let tabs = NSTabView(frame: content.bounds)
        tabs.autoresizingMask = [.width, .height]
        content.addSubview(tabs)

        let general = NSTabViewItem(identifier: "general")
        general.label = "General"
        general.view = makeGeneralView()
        tabs.addTabViewItem(general)

        let providersTab = NSTabViewItem(identifier: "providers")
        providersTab.label = "Providers"
        providersTab.view = makeProvidersView()
        tabs.addTabViewItem(providersTab)

        let advanced = NSTabViewItem(identifier: "advanced")
        advanced.label = "Advanced"
        advanced.view = makeAdvancedView()
        tabs.addTabViewItem(advanced)
    }

    private func makeGeneralView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
        ])

        let intervals: [(String, TimeInterval)] = [("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300), ("15 minutes", 900), ("30 minutes", 1800)]
        let popup = NSPopUpButton()
        for entry in intervals { popup.addItem(withTitle: entry.0) }
        if let index = intervals.firstIndex(where: { $0.1 == Preferences.shared.refreshInterval }) {
            popup.selectItem(at: index)
        }
        popup.target = self
        popup.action = #selector(refreshIntervalChanged(_:))
        stack.addArrangedSubview(labeledRow("Refresh interval", control: popup))

        stack.addArrangedSubview(checkBox("Merge provider icons", state: Preferences.shared.mergeIcons, action: #selector(mergeChanged(_:))))
        stack.addArrangedSubview(checkBox("Show highest used percentage", state: Preferences.shared.showPercentage, action: #selector(percentageChanged(_:))))
        stack.addArrangedSubview(checkBox("Launch at login", state: Preferences.shared.launchAtLogin, action: #selector(loginChanged(_:))))
        stack.addArrangedSubview(checkBox("Automatically download updates", state: Preferences.shared.automaticUpdates, action: #selector(autoUpdatesChanged(_:))))
        return view
    }

    private func makeProvidersView() -> NSView {
        let view = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("provider"))
        column.title = "Provider"
        column.width = 430
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = false

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let buttons = NSStackView()
        buttons.orientation = .vertical
        buttons.alignment = .leading
        buttons.spacing = 6
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let firstRow = NSStackView()
        firstRow.orientation = .horizontal
        firstRow.spacing = 8
        firstRow.addArrangedSubview(button("Refresh list", #selector(refreshProviders)))
        setAPIKeyButton.target = self
        setAPIKeyButton.action = #selector(setAPIKey)
        setAPIKeyButton.bezelStyle = .rounded
        setAPIKeyButton.isEnabled = false
        firstRow.addArrangedSubview(setAPIKeyButton)
        firstRow.addArrangedSubview(button("Refresh browser session…", #selector(refreshBrowserSession)))
        buttons.addArrangedSubview(firstRow)

        let secondRow = NSStackView()
        secondRow.orientation = .horizontal
        secondRow.spacing = 8
        secondRow.addArrangedSubview(button("Clear browser cache", #selector(clearBrowserSession)))
        secondRow.addArrangedSubview(button("Open config file", #selector(openConfig)))
        secondRow.addArrangedSubview(button("Provider docs", #selector(openDocs)))
        buttons.addArrangedSubview(secondRow)
        view.addSubview(buttons)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            buttons.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),
            statusLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])
        return view
    }

    private func makeAdvancedView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
        ])
        stack.addArrangedSubview(button("Check for updates", #selector(checkUpdates)))
        stack.addArrangedSubview(button("Validate provider configuration", #selector(validateConfig)))
        stack.addArrangedSubview(button("Open logs folder", #selector(openLogs)))
        return view
    }

    func numberOfRows(in tableView: NSTableView) -> Int { providers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let provider = providers[row]
        let cell = NSTableCellView()

        // Keep the checkbox separate from the provider label. In the old cell the
        // checkbox occupied the full row, so every click toggled the provider and
        // NSTableView never received a row-selection click. That made Set API key
        // permanently report “Select a provider first.”
        let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(providerToggled(_:)))
        toggle.state = provider.enabled ? .on : .off
        toggle.tag = row
        toggle.frame = NSRect(x: 8, y: 3, width: 24, height: 24)
        toggle.toolTip = provider.enabled ? "Disable \(provider.name)" : "Enable \(provider.name)"
        cell.addSubview(toggle)

        let label = NSTextField(labelWithString: provider.name)
        label.frame = NSRect(x: 38, y: 4, width: 380, height: 22)
        label.lineBreakMode = .byTruncatingTail
        cell.textField = label
        cell.addSubview(label)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateProviderSelectionStatus()
    }

    private func reloadProviders() async {
        let selectedID = selectedProvider()?.id
        do {
            providers = try await client.listProviders()
            table.reloadData()
            if let selectedID, let index = providers.firstIndex(where: { $0.id == selectedID }) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                table.scrollRowToVisible(index)
            }
            if table.selectedRow < 0 {
                setAPIKeyButton.isEnabled = false
                statusLabel.stringValue = "\(providers.count) providers detected. Click a provider name to configure it."
            } else {
                updateProviderSelectionStatus()
            }
        } catch {
            setAPIKeyButton.isEnabled = false
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func providerToggled(_ sender: NSButton) {
        guard providers.indices.contains(sender.tag) else { return }
        table.selectRowIndexes(IndexSet(integer: sender.tag), byExtendingSelection: false)
        let provider = providers[sender.tag]
        statusLabel.stringValue = sender.state == .on
            ? "Enabling \(provider.name)…"
            : "Disabling \(provider.name)…"
        Task {
            do {
                try await client.setProvider(provider.id, enabled: sender.state == .on)
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                await reloadProviders()
            } catch {
                statusLabel.stringValue = error.localizedDescription
                sender.state = provider.enabled ? .on : .off
            }
        }
    }

    @objc private func setAPIKey() {
        guard let provider = selectedProvider() else {
            statusLabel.stringValue = "Select a provider name first."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Set API key for \(provider.name)"
        alert.informativeText = "The key is passed to the upstream CodexBarCLI over stdin and stored in its protected config file."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }
        statusLabel.stringValue = "Saving API key for \(provider.name)…"
        Task {
            do {
                try await client.setAPIKey(input.stringValue, provider: provider.id)
                NotificationCenter.default.post(name: .providerConfigurationChanged, object: provider.id)
                await reloadProviders()
                if provider.id == "zai" {
                    statusLabel.stringValue = "z.ai key saved. Verifying the API connection…"
                    do {
                        _ = try await client.probeAPIProvider(provider.id)
                        statusLabel.stringValue = "z.ai API key saved and verified."
                    } catch {
                        statusLabel.stringValue = "z.ai key was saved, but verification failed: \(error.localizedDescription)"
                    }
                } else {
                    statusLabel.stringValue = "API key saved for \(provider.name)."
                }
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func refreshBrowserSession() {
        guard let provider = selectedProvider() else {
            statusLabel.stringValue = "Select a provider first."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Refresh browser session for \(provider.name)?"
        alert.informativeText = "This invokes the upstream cookie importer and may show a macOS Keychain permission prompt. Existing cached cookies remain intact if import fails."
        alert.addButton(withTitle: "Refresh")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let result = try await client.refreshBrowserSession(provider: provider.id)
                statusLabel.stringValue = result.isEmpty ? "Browser session refreshed for \(provider.name)." : result
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func clearBrowserSession() {
        guard let provider = selectedProvider() else {
            statusLabel.stringValue = "Select a provider first."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Clear cached browser session for \(provider.name)?"
        alert.informativeText = "The next refresh will need a valid browser or manual session again."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let result = try await client.clearBrowserSession(provider: provider.id)
                statusLabel.stringValue = result.isEmpty ? "Browser cache cleared for \(provider.name)." : result
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func openConfig() {
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
                try FileManager.default.createDirectory(
                    at: xdg.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                let emptyConfig = """
                {
                  "version": 1,
                  "hooks": null,
                  "providers": []
                }
                """
                try Data((emptyConfig + "\n").utf8).write(to: xdg, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: xdg.path)
            } catch {
                statusLabel.stringValue = "Could not create config file: \(error.localizedDescription)"
                return
            }
        }
        NSWorkspace.shared.open(target)
    }

    @objc private func openDocs() {
        guard table.selectedRow >= 0, providers.indices.contains(table.selectedRow) else { return }
        let provider = providers[table.selectedRow]
        NSWorkspace.shared.open(ProviderCatalog.documentationURL(for: provider.id))
    }

    @objc private func refreshProviders() { Task { await reloadProviders() } }
    @objc private func checkUpdates() { updater.checkForUpdates() }

    @objc private func validateConfig() {
        Task {
            do {
                let result = try await client.validateConfig()
                showText(title: "Configuration validation", text: result)
            } catch {
                showText(title: "Configuration validation failed", text: error.localizedDescription)
            }
        }
    }

    @objc private func openLogs() {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CodexBarMonterey")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logs)
    }

    @objc private func refreshIntervalChanged(_ sender: NSPopUpButton) {
        let values: [TimeInterval] = [60, 120, 300, 900, 1800]
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        Preferences.shared.refreshInterval = values[sender.indexOfSelectedItem]
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func mergeChanged(_ sender: NSButton) {
        Preferences.shared.mergeIcons = sender.state == .on
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func percentageChanged(_ sender: NSButton) {
        Preferences.shared.showPercentage = sender.state == .on
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func loginChanged(_ sender: NSButton) { Preferences.shared.launchAtLogin = sender.state == .on }

    @objc private func autoUpdatesChanged(_ sender: NSButton) {
        Preferences.shared.automaticUpdates = sender.state == .on
        updater.setAutomatic(sender.state == .on)
    }

    private func updateProviderSelectionStatus() {
        guard let provider = selectedProvider() else {
            setAPIKeyButton.isEnabled = false
            statusLabel.stringValue = "Select a provider name first."
            return
        }
        setAPIKeyButton.isEnabled = true
        statusLabel.stringValue = "Selected \(provider.name) (provider ID: \(provider.id))."
    }

    private func selectedProvider() -> ProviderDescriptor? {
        guard table.selectedRow >= 0, providers.indices.contains(table.selectedRow) else { return nil }
        return providers[table.selectedRow]
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func checkBox(_ title: String, state: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = state ? .on : .off
        return button
    }

    private func labeledRow(_ title: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        let label = NSTextField(labelWithString: title)
        label.frame.size.width = 140
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func showText(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 480, height: 260)
        if let field = scroll.documentView as? NSTextView {
            field.string = text
            field.isEditable = false
            field.isSelectable = true
            field.isRichText = false
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = .labelColor
            field.backgroundColor = .textBackgroundColor
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("CodexBarMonterey.preferencesChanged")
    static let providerConfigurationChanged = Notification.Name("CodexBarMonterey.providerConfigurationChanged")
}
