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
client = (SOURCES / "CLIClient.swift").read_text()
parser = (SOURCES / "DashboardParser.swift").read_text()

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

# A newly created config must have the upstream versioned root shape, never `{}`.
assert '"version": 1' in settings
assert 'Data("{}\\n".utf8)' not in settings

print("Original-style Monterey UI contract tests passed.")
