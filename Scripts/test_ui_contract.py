#!/usr/bin/env python3
"""Fast source-level regressions for the original-style Monterey UI."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "CodexBarMonterey"

menu = (SOURCES / "MenuController.swift").read_text()
popover = (SOURCES / "DashboardPopoverController.swift").read_text()
views = (SOURCES / "DashboardViews.swift").read_text()
settings = (SOURCES / "SettingsWindowController.swift").read_text()
details = (SOURCES / "DetailsWindowController.swift").read_text()
client = (SOURCES / "CLIClient.swift").read_text()
parser = (SOURCES / "DashboardParser.swift").read_text()
store = (SOURCES / "DashboardStore.swift").read_text()
cost_payload = (SOURCES / "CostHistoryPayload.swift").read_text()
quota_trend = (SOURCES / "LocalQuotaTrendStore.swift").read_text()
provider_auth = (SOURCES / "ProviderAuthentication.swift").read_text()
config_store = (SOURCES / "CodexBarConfigStore.swift").read_text()

# The status item must open a custom popover rather than a native NSMenu.
assert "NSPopover" in popover
assert "DashboardPopoverView" in popover
assert "statusButtonClicked" in menu
assert ".menu =" not in menu

# Original-style UI contract: provider switcher, summary card, charts, actions.
for token in [
    "ProviderSwitcherButton",
    "DashboardSummaryCard",
    "MiniHistoryChart",
    "ProviderDetailPanelView",
    "Usage Dashboard",
    "Status Page",
]:
    assert token in views, token

# Details window must host graphical provider dashboards, never raw blank text.
assert "AllProvidersDashboardView" in details
assert "NSTextView.scrollableTextView" not in details

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
assert 'zai-five-hour-trend-v2.json' in quota_trend
assert 'abs(minutes - 300) <= 1' in quota_trend
assert 'return values.max()' not in quota_trend
assert "quota_trend_store_regression.swift" in (ROOT / "Scripts" / "test_cost_history_parser.sh").read_text()
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

# A newly created config must have the upstream versioned root shape, never `{}`.
assert '"version": 1' in config_store
assert 'Data("{}\\n".utf8)' not in settings



print("All-provider authentication UI contract tests passed.")
