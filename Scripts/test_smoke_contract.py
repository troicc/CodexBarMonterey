#!/usr/bin/env python3
"""Fast regression tests for the offline smoke-test provider contract."""

from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "Scripts" / "validate_provider_catalog.py"
spec = importlib.util.spec_from_file_location("provider_validator", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = [{"provider": "codex"}] + [
    {"provider": f"provider-{index}"} for index in range(1, 60)
]
assert len(module.validate(rows, 60)) == 60
assert module.provider_ids({"providers": [{"id": "codex"}]}) == ["codex"]

for invalid in (
    [],
    [{"provider": "codex"}, {"provider": "codex"}],
    [{"displayName": "Missing ID"}],
):
    try:
        module.validate(invalid, 1)
    except ValueError:
        pass
    else:
        raise AssertionError(f"invalid provider catalog was accepted: {invalid!r}")

smoke = (ROOT / "Scripts" / "smoke_test_app.sh").read_text()
assert "printf '{}" not in smoke, "offline smoke test must not create an invalid empty config"
assert "validate_provider_catalog.py" in smoke
assert "Skipped live usage fetching" in smoke
print("Offline smoke-test contract regression tests passed.")
