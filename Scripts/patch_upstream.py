#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys


def lower_platform(package: Path) -> None:
    if not package.exists():
        raise SystemExit(f"Package manifest not found: {package}")
    original = package.read_text()
    pattern = re.compile(r"\.macOS\(\.v(\d+)\)")
    versions = [int(value) for value in pattern.findall(original)]
    if not versions:
        raise SystemExit(f"No macOS platform declaration found in {package}")
    updated, count = pattern.subn(".macOS(.v12)", original)
    if count == 0:
        raise SystemExit(f"Could not patch deployment target in {package}")
    package.write_text(updated)
    print(f"Patched {package}: macOS {max(versions)} -> 12")


def use_local_commander(package: Path) -> None:
    original = package.read_text()
    pattern = re.compile(
        r'\.package\(url:\s*"https://github\.com/steipete/Commander(?:\.git)?",\s*'
        r'(?:from|exact):\s*"[^"]+"\)'
    )
    updated, count = pattern.subn('.package(path: "../Commander")', original)
    if count != 1:
        raise SystemExit(f"Expected one Commander dependency in {package}, patched {count}")
    package.write_text(updated)
    print(f"Patched {package}: use local Commander checkout")


def apply_optional_patch(repo: Path, patch: Path) -> None:
    if not patch.exists():
        return
    subprocess.run(
        ["git", "-C", str(repo), "apply", "--check", str(patch)],
        check=True,
    )
    subprocess.run(["git", "-C", str(repo), "apply", str(patch)], check=True)
    print(f"Applied source compatibility patch: {patch}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: patch_upstream.py /path/to/Vendor/CodexBar")
    codexbar = Path(sys.argv[1]).resolve()
    vendor = codexbar.parent
    project_root = vendor.parent
    sweet = vendor / "SweetCookieKit"
    commander = vendor / "Commander"

    use_local_commander(codexbar / "Package.swift")
    lower_platform(codexbar / "Package.swift")
    lower_platform(sweet / "Package.swift")
    lower_platform(commander / "Package.swift")

    # Optional source-level shims live outside Vendor so a freshly cloned upstream
    # tree can be patched reproducibly when newer SDK APIs need Monterey fallbacks.
    patch_dir = project_root / "Patches"
    apply_optional_patch(codexbar, patch_dir / "CodexBar.patch")
    apply_optional_patch(sweet, patch_dir / "SweetCookieKit.patch")
    apply_optional_patch(commander, patch_dir / "Commander.patch")


if __name__ == "__main__":
    main()
