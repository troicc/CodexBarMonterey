#!/usr/bin/env python3
"""Fast source-level regressions for the Monterey AppKit shell UI wiring."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "CodexBarMonterey"

settings = (SOURCES / "SettingsWindowController.swift").read_text()
details = (SOURCES / "DetailsWindowController.swift").read_text()
menu = (SOURCES / "MenuController.swift").read_text()
client = (SOURCES / "CLIClient.swift").read_text()
provider_view = (SOURCES / "ProviderMenuView.swift").read_text()

# Provider selection must be independent from its enable/disable checkbox.
assert 'checkboxWithTitle: ""' in settings
assert "tableViewSelectionDidChange" in settings
assert "setAPIKeyButton.isEnabled = true" in settings
assert "table.selectRowIndexes" in settings

# A newly created config must have the upstream versioned root shape, never `{}`.
assert '"version": 1' in settings
assert 'try Data("{}\\n".utf8)' not in settings

# Details windows need AppKit's correctly wired scrollable text system.
assert "NSTextView.scrollableTextView()" in details
assert "textView.textColor = .labelColor" in details
assert "window?.makeKeyAndOrderFront(nil)" in details

# Nested menu actions must have explicit targets or AppKit disables them.
assert "submenu.autoenablesItems = false" in menu
assert "item.target = self" in menu
assert "addSubmenuItem(" in menu

# z.ai API-key configuration and verification must use the stable provider ID.
assert 'provider.id == "zai"' in settings
assert "probeAPIProvider" in client
assert '"--source", "api"' in client
assert "z.ai requires an API key" in provider_view

print("Monterey UI interaction contract tests passed.")
