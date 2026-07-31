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
assert "probeAPIProvider" in client
assert '"--source", "api"' in client

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
assert "quota_trend_store_regression.swift" in (ROOT / "Scripts" / "test_cost_history_parser.sh").read_text()
assert 'title: "Quota trend"' in parser
assert "Local quota samples" in views
assert 'fixedMaximum: dashboard.id == "zai" ? 100 : nil' in views
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
assert '"version": 1' in settings
assert 'Data("{}\\n".utf8)' not in settings


# Legacy Swift 5.6 optional-binding syntax contract. Swift 5.7 shorthand such
# as `guard let value else` must not be reintroduced into the Monterey shell.
legacy_binding = re.compile(
    r"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?=,|else\b|\{)"
)
for swift_file in SOURCES.glob("*.swift"):
    swift_source = swift_file.read_text()
    match = legacy_binding.search(swift_source)
    assert match is None, f"Swift 5.7 optional-binding shorthand in {swift_file.name}: {match.group(0)}"

print("Today-token and local z.ai trend UI contract tests passed.")
