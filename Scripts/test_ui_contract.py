#!/usr/bin/env python3
"""Fast source-level regressions for the original-style Monterey UI."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "CodexBarMonterey"

menu = (SOURCES / "MenuController.swift").read_text()
popover = (SOURCES / "DashboardPopoverController.swift").read_text()
views = (SOURCES / "DashboardViews.swift").read_text()
settings = (SOURCES / "SettingsWindowController.swift").read_text()
details = (SOURCES / "DetailsWindowController.swift").read_text()
detail_panel = (SOURCES / "ProviderDetailPanelController.swift").read_text()
client = (SOURCES / "CLIClient.swift").read_text()
parser = (SOURCES / "DashboardParser.swift").read_text()
store = (SOURCES / "DashboardStore.swift").read_text()
cost_payload = (SOURCES / "CostHistoryPayload.swift").read_text()
quota_trend = (SOURCES / "LocalQuotaTrendStore.swift").read_text()
local_spend = (SOURCES / "LocalSpendHistoryStore.swift").read_text()
models = (SOURCES / "Models.swift").read_text()
provider_auth = (SOURCES / "ProviderAuthentication.swift").read_text()
config_store = (SOURCES / "CodexBarConfigStore.swift").read_text()

# Left click keeps the compact popover; the status item itself is not permanently
# bound to an NSMenu because right click builds a contextual menu on demand.
assert "NSPopover" in popover
assert "DashboardPopoverView" in popover
assert "statusButtonClicked" in menu
assert ".menu =" not in menu
assert "event.type == .rightMouseUp" in menu
assert "event.modifierFlags.contains(.control)" in menu
assert "NSMenu.popUpContextMenu" in menu
assert "NSApp.mainMenu = mainMenu" in menu
assert "setAccessibilityLabel" in menu

# Original-style UI contract: provider switcher, summary card, charts, actions.
for token in [
    "ProviderSwitcherButton",
    "DashboardSummaryCard",
    "MiniHistoryChart",
    "LiveProviderDetailPanelView",
    "ProviderDetailPanelView",
    "Usage Dashboard",
    "Status Page",
    "keyboardShortcut",
]:
    assert token in views, token

# Details window must host graphical provider dashboards, never raw blank text.
assert "AllProvidersDashboardView" in details
assert "NSTextView.scrollableTextView" not in details
assert "setFrameAutosaveName" in settings
assert "setFrameAutosaveName" in details
assert "setFrameAutosaveName" in detail_panel
assert "LiveProviderDetailPanelView" in detail_panel

# API key UX must support direct paste and a persistent secure field.
assert "SecureField" in settings
assert "pasteAPIKey" in settings
assert "NSPasteboard.general.string" in settings
assert "Save & Verify" in settings
assert "probeProvider" in client
assert "saveCredential" in client
assert "ProviderAuthenticationCatalog" in settings
assert 'status = "Save failed:' in settings
assert "Saved, but verification failed" not in settings
assert 'tokenAccount("deepseek"' in provider_auth
assert 'tokenAccount("venice"' in provider_auth
assert 'case .tokenAccount:' in config_store
assert 'provider["tokenAccounts"]' in config_store
assert 'provider["apiKey"] = secret' in config_store
assert 'provider["cookieSource"] = "manual"' in config_store
assert 'provider["enterpriseHost"] = host' in config_store
assert 'provider["workspaceID"] = workspace' in config_store
assert 'provider["region"] = region' in config_store
assert ".posixPermissions: 0o600" in config_store
assert "makeBackup" in config_store
assert "restore(_ backup:" in config_store
assert "configStore.restore(backup)" in client
assert "rollbackFailed" in client
assert "try await probeProvider(provider, profile: profile)" in client
assert "previous configuration was restored" in client
assert "let receipt = try configStore.save" in client

# Provider dashboard JSON must be enriched from the upstream CLI and parsed
# tolerantly so provider-specific histories can render without lockstep schemas.
assert "dashboardSupplementJSON" in client
assert "extractHistory" in parser
assert "today-spend" in parser
assert "30d-tokens" in parser

# Codex cost history must use the documented aggregate fields, not a fuzzy
# recursive match that can select `daily[].totalTokens` at random.
assert "last30DaysTokens" in cost_payload
assert "last30DaysCostUSD" in cost_payload
assert "resolvedTodayTokens" in cost_payload
assert 'title: "Today tokens"' in parser
assert "LocalQuotaTrendStore" in store
assert 'snapshot.provider == "zai"' in quota_trend
assert 'zai-five-hour-trend-v3.json' in quota_trend
assert 'abs(minutes - 300) <= 1' in quota_trend
assert 'return values.max()' not in quota_trend
assert "StableIdentifier.hash(snapshot.id)" in quota_trend
assert "quota_trend_store_regression.swift" in (ROOT / "Scripts" / "test_cost_history_parser.sh").read_text()
assert "local_spend_history_regression.swift" in (ROOT / "Scripts" / "test_cost_history_parser.sh").read_text()
assert "maximumAttributableInterval" in local_spend
assert "unattributedIntervals" in local_spend
assert "calendar.isDate(previous.timestamp, inSameDayAs: next.timestamp)" in local_spend
assert "StableIdentifier.hash(accountKey)" in local_spend
assert "usage?.identity?.accountEmail" in models
assert "usage?.accountEmail" in models
# z.ai must use real hourly token usage rather than presenting locally sampled
# quota percentages as token history.
assert "private static func zaiPayload" in parser
assert 'dictionary(named: "zaiUsage"' in parser
assert 'title: "24h tokens"' in parser
assert 'value: "Not exposed"' in parser
assert 'title: "5-hour trend"' not in parser
assert "Local 5-hour samples" not in views
assert 'fixedMaximum: dashboard.id == "zai" ? 100 : nil' not in views
assert "fixedMaximum: nil" in views
assert 'Text("Hourly token usage")' in views
assert '"30dtokens", "thirtydaytokens", "totaltokens"' not in parser
assert "supplementalJSONBySnapshot" in store
assert "fetchedSupplement ??" in store
assert "providerAccountCount <= 1" in store
assert "refreshPending = true" in store
assert "snapshotGeneration" in store
assert "generation == snapshotGeneration" in store
assert "let snapshot = snapshots.first(where: { $0.id == key })" in store
assert "store.onRefreshStateChanged" in menu
assert "self?.rebuildStatusItems()" in menu
assert "RefreshStatusBanner" in views
assert '["cost", "--provider", provider' in client
assert '["--provider", provider, "--format", "json"' not in client

# Swift 6.3 requires StrokeStyle labels in declaration order. Catch the exact
# ordering bug before the macOS build step.
assert "StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)" in views
assert "StrokeStyle(lineWidth: 3, lineJoin: .round, lineCap: .round)" not in views

# The Monterey popover must stay close to the compact original menu footprint,
# use a dark-blue material overlay, and avoid provider-colored full-card fills.
assert "NSSize(width: 328, height: 520)" in popover
assert "DashboardTheme.backgroundTop" in views
assert "DashboardTheme.selection.opacity(0.88)" in views
assert "DashboardTheme.cardStart" in views
assert "ProviderBrand.color(for: dashboard.id).opacity(0.95)" not in views
assert ".frame(height: switcherHeight)" in views
assert ".frame(maxHeight: 174)" not in views
assert "ScrollView(.vertical, showsIndicators: true)" in views
assert ".accessibilityValue" in views

# A newly created config must have the upstream versioned root shape, never `{}`.
assert '"version": 1' in config_store
assert 'Data("{}\\n".utf8)' not in settings
assert "revealAPIKey = false" in settings
assert "Open Console logs" in settings
assert "Library/Logs/CodexBarMonterey" not in settings



print("All-provider authentication UI contract tests passed.")
