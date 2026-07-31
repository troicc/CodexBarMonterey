#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/CodexBarMonterey/ProviderAuthentication.swift").read_text()

stable_match = re.search(r"static let stableProviderIDs: \[String\] = \[(.*?)\n    \]", source, re.S)
assert stable_match, "stableProviderIDs not found"
stable = re.findall(r'"([a-z0-9_-]+)"', stable_match.group(1))

constructors = re.findall(
    r'\b(?:api|tokenAccount|cookie|fields|external)\("([a-z0-9_-]+)"',
    source,
)

assert len(stable) == len(set(stable)), "Duplicate stable provider IDs"
assert len(constructors) == len(set(constructors)), "Duplicate authentication profiles"
missing = sorted(set(stable) - set(constructors))
extra = sorted(set(constructors) - set(stable))
assert not missing, f"Providers without explicit authentication profile: {missing}"
assert not extra, f"Authentication profiles for unknown providers: {extra}"
assert "deepseek" in stable and "xai" in stable
assert 'tokenAccount("deepseek"' in source
assert 'api("xai"' in source
assert len(stable) >= 66, len(stable)

print(f"Provider authentication catalog audit passed: {len(stable)} explicit providers.")
