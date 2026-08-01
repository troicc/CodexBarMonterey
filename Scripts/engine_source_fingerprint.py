#!/usr/bin/env python3
"""Print a deterministic fingerprint for inputs that produce Vendor/CodexBar."""

from hashlib import sha256
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
inputs = [
    ROOT / "ENGINE_VERSION",
    ROOT / "Scripts" / "engine_source_fingerprint.py",
    ROOT / "Scripts" / "fetch_engine.sh",
    ROOT / "Scripts" / "patch_upstream.py",
    ROOT / "Patches" / "MontereyCompat.swift",
]
inputs.extend(sorted((ROOT / "Patches").glob("*.patch")))

digest = sha256()
for path in inputs:
    relative = path.relative_to(ROOT).as_posix().encode("utf-8")
    contents = path.read_bytes()
    digest.update(len(relative).to_bytes(8, "big"))
    digest.update(relative)
    digest.update(len(contents).to_bytes(8, "big"))
    digest.update(contents)

print(digest.hexdigest())
