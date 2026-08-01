#!/usr/bin/env python3
"""Source-level release regressions for universal archives and Sparkle updates."""

from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
release = (ROOT / ".github" / "workflows" / "release.yml").read_text()
build = (ROOT / ".github" / "workflows" / "build.yml").read_text()
universal = (ROOT / "Scripts" / "build_universal.sh").read_text()
smoke = (ROOT / "Scripts" / "smoke_test_app.sh").read_text()
build_app = (ROOT / "Scripts" / "build_app.sh").read_text()
build_engine = (ROOT / "Scripts" / "build_engine.sh").read_text()
fetch_engine = (ROOT / "Scripts" / "fetch_engine.sh").read_text()
local_validation = (ROOT / "Scripts" / "build_local_validation.sh").read_text()
local_install = (ROOT / "Scripts" / "install_local.sh").read_text()

# appcast.xml is a generated release artifact, but it must be trackable because
# Sparkle clients read the copy published to origin/main.
ignored = subprocess.run(
    ["git", "check-ignore", "--quiet", "appcast.xml"],
    cwd=ROOT,
    check=False,
)
assert ignored.returncode == 1, "appcast.xml is still ignored"
assert "git add --force appcast.xml" in release

# Tags from side branches must not publish an appcast commit onto main, and two
# releases must not race while updating the feed.
assert 'git merge-base --is-ancestor "$GITHUB_SHA" origin/main' in release
assert "group: release-appcast-${{ github.repository }}" in release
assert "cancel-in-progress: false" in release
assert 'MAIN_WORKTREE_PARENT="$(mktemp -d)"' in release
assert "git pull --rebase origin main" in release

# Universal verification must cover every nested Mach-O, not just the app and
# CLI entry points. Both CI workflows run this contract before building.
for token in [
    "Intel build is missing Mach-O component",
    "Apple Silicon build is missing Mach-O component",
    "Universal bundle contains a single-architecture component",
    "mach_o_count",
]:
    assert token in universal, token
assert "find \"$APP\" -type f -print0" in smoke
assert "Bundle contains a non-universal Mach-O component" in smoke
assert "python3 Scripts/test_release_contract.py" in build
assert "python3 Scripts/test_release_contract.py" in release

# A local incremental build must not silently reuse an engine produced from a
# different upstream version or patch set.
fingerprint = subprocess.check_output(
    [sys.executable, str(ROOT / "Scripts" / "engine_source_fingerprint.py")],
    text=True,
).strip()
assert re.fullmatch(r"[0-9a-f]{64}", fingerprint), fingerprint
assert '"$ROOT/Scripts/build_engine.sh" "$ARCH"' in build_app
assert "EXPECTED_FINGERPRINT" in build_engine
assert "EXPECTED_VERSION" in build_engine
assert 'Vendor/.engine-version' in build_engine
assert 'Vendor/.source-fingerprint' in build_engine
assert '"$VENDOR/.engine-version"' in fetch_engine
assert '"$VENDOR/.source-fingerprint"' in fetch_engine

# Swift 5.6-era Monterey machines can build the current UI shell directly for
# both architectures by reusing a previously validated helper/framework bundle.
# This is deliberately separate from the authoritative full engine build.
for token in [
    'CODEXBAR_LOCAL_TEMPLATE_APP',
    '-target "$arch-apple-macosx12.0"',
    'lipo -create',
    'codesign --force --deep --sign -',
    'CODEXBAR_SMOKE_OFFLINE=1',
    'This bundle is ad-hoc signed and is not a release artifact.',
]:
    assert token in local_validation, token
assert '"$ROOT/Scripts/build_engine.sh"' not in local_validation
assert 'BACKUP_APP="$BACKUP_ROOT/CodexBar Monterey.app"' in local_install
assert "restore_previous_app" in local_install

print("Release contract tests passed.")
