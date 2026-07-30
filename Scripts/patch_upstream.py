#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess
import sys


CORE_RELATIVE = Path("Sources/CodexBarCore")
SHIM_NAME = "MontereyCompat.swift"


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


def replace_required(text: str, old: str, new: str, *, label: str, expected: int | None = None) -> tuple[str, int]:
    count = text.count(old)
    if expected is not None and count != expected:
        raise SystemExit(f"{label}: expected {expected} occurrence(s), found {count}")
    if count == 0:
        raise SystemExit(f"{label}: upstream source pattern was not found")
    return text.replace(old, new), count


def backport_regex_apis(relative: Path, text: str) -> tuple[str, int]:
    changes = 0

    if relative == Path("Providers/Codex/CodexStatusProbe.swift"):
        replacements = (
            (
                'if let match = raw.firstMatch(of: /^([0-9]{1,2}:[0-9]{2}) on ([0-9]{1,2} [A-Za-z]{3})$/) {',
                'if let match = raw.montereyFirstRegexCaptures(#"^([0-9]{1,2}:[0-9]{2}) on ([0-9]{1,2} [A-Za-z]{3})$"#), match.count >= 3 {',
                "first reset-date regex",
            ),
            (
                'if let match = raw.firstMatch(of: /^([0-9]{1,2}:[0-9]{2}) on ([A-Za-z]{3} [0-9]{1,2})$/) {',
                'if let match = raw.montereyFirstRegexCaptures(#"^([0-9]{1,2}:[0-9]{2}) on ([A-Za-z]{3} [0-9]{1,2})$"#), match.count >= 3 {',
                "second reset-date regex",
            ),
        )
        for old, new, label in replacements:
            text, count = replace_required(text, old, new, label=f"{relative}: {label}", expected=1)
            changes += count
        text, count = replace_required(
            text,
            'raw = "\\(match.output.2) \\(match.output.1)"',
            'raw = "\\(match[2]) \\(match[1])"',
            label=f"{relative}: reset-date captures",
            expected=2)
        changes += count

    if relative == Path("Providers/Doubao/DoubaoUsageFetcher.swift"):
        replacements = (
            ('        let pattern = /(\\d+)([dhms])/\n', '', "regex declaration"),
            ('for match in trimmed.matches(of: pattern) {',
             'for match in trimmed.montereyRegexCaptures(#"(\\d+)([dhms])"#) {', "regex iteration"),
            ('guard let num = Double(match.1) else { continue }',
             'guard match.count >= 3, let num = Double(match[1]) else { continue }', "numeric capture"),
            ('switch match.2 {', 'switch match[2] {', "unit capture"),
        )
        for old, new, label in replacements:
            text, count = replace_required(text, old, new, label=f"{relative}: {label}", expected=1)
            changes += count

    if relative == Path("Providers/Kiro/KiroStatusProbe.swift"):
        old = 'let numbers = creditsStr.matches(of: /(\\d+\\.?\\d*)/)'
        new = 'let numbers = creditsStr.montereyRegexCaptures(#"(\\d+\\.?\\d*)"#).compactMap { $0.count > 1 ? $0[1] : nil }'
        text, count = replace_required(text, old, new, label=f"{relative}: credits regex", expected=1)
        changes += count

        old = 'let numbers = bonusStr.matches(of: /(\\d+\\.?\\d*)/)'
        new = 'let numbers = bonusStr.montereyRegexCaptures(#"(\\d+\\.?\\d*)"#).compactMap { $0.count > 1 ? $0[1] : nil }'
        text, count = replace_required(text, old, new, label=f"{relative}: bonus regex", expected=1)
        changes += count

        replacements = {
            'Double(String(numbers[0].output.1))': 'Double(numbers[0])',
            'Double(String(numbers[1].output.1))': 'Double(numbers[1])',
        }
        for old, new in replacements.items():
            count = text.count(old)
            if count == 0:
                raise SystemExit(f"{relative}: expected output capture pattern {old!r}")
            text = text.replace(old, new)
            changes += count

    return text, changes


def transform_core_source(relative: Path, text: str) -> tuple[str, int]:
    """Backport the macOS 13/14 APIs reported by the real Monterey CI build."""
    changes = 0

    # Swift Clock/Duration and the modern lock are runtime-gated to macOS 13.
    for pattern, replacement in (
        (r"\bContinuousClock\b", "MontereyContinuousClock"),
        (r"\bOSAllocatedUnfairLock\b", "MontereyStateLock"),
        (r"\bDuration\b", "MontereyDuration"),
    ):
        text, count = re.subn(pattern, replacement, text)
        changes += count

    # Foundation API spelling introduced in macOS 13. Older equivalents preserve
    # the relevant behavior for the upstream call sites in v0.46.0.
    literal_replacements = (
        (".host(percentEncoded:", ".montereyHost(percentEncoded:"),
        (".appending(queryItems:", ".montereyAppending(queryItems:"),
        (".appending(path:", ".appendingPathComponent("),
        (".append(path:", ".appendPathComponent("),
        (".trimmingPrefix(", ".montereyTrimmingPrefix("),
        ('split(separator: " - ")', 'montereySplit(separator: " - ")'),
        ('split(separator: "::")', 'montereySplit(separator: "::")'),
        ("TimeZone(secondsFromGMT: 0) ?? .gmt", "TimeZone(secondsFromGMT: 0)!"),
    )
    for old, new in literal_replacements:
        count = text.count(old)
        if count:
            text = text.replace(old, new)
            changes += count

    text, regex_changes = backport_regex_apis(relative, text)
    changes += regex_changes

    if relative == Path("OpenAIWeb/OpenAIDashboardWebsiteDataStore.swift"):
        old = """        let id = Self.identifier(forStorageKey: storageKey)
        let store = WKWebsiteDataStore(forIdentifier: id)
        self.cachedStores[storageKey] = store"""
        new = """        let store: WKWebsiteDataStore
        if #available(macOS 14.0, *) {
            let id = Self.identifier(forStorageKey: storageKey)
            store = WKWebsiteDataStore(forIdentifier: id)
        } else {
            // Monterey has no persistent data-store identifiers. Use the default
            // persistent store so browser-based providers still retain login state.
            store = .default()
        }
        self.cachedStores[storageKey] = store"""
        text, count = replace_required(text, old, new, label=f"{relative}: WebKit data store", expected=1)
        changes += count

    return text, changes


def scan_for_unavailable_apis(core: Path) -> None:
    checks: tuple[tuple[str, re.Pattern[str]], ...] = (
        ("native Duration", re.compile(r"\bDuration\b")),
        ("native ContinuousClock", re.compile(r"\bContinuousClock\b")),
        ("OSAllocatedUnfairLock", re.compile(r"\bOSAllocatedUnfairLock\b")),
        ("Swift Regex firstMatch", re.compile(r"\.firstMatch\(of:")),
        ("Swift Regex matches", re.compile(r"\.matches\(of:")),
        ("URL.host(percentEncoded:)", re.compile(r"\.host\(percentEncoded:")),
        ("URL.appending(queryItems:)", re.compile(r"\.appending\(queryItems:")),
        ("URL.appending(path:)", re.compile(r"\.appending\(path:")),
        ("URL.append(path:)", re.compile(r"\.append\(path:")),
        ("String.trimmingPrefix", re.compile(r"\.trimmingPrefix\(")),
        ("multi-character String.split", re.compile(r"\.split\(separator:\s*\"(?: - |::)\"")),
        ("TimeZone.gmt", re.compile(r"\?\?\s*\.gmt\b")),
    )
    failures: list[str] = []
    for source in sorted(core.rglob("*.swift")):
        if source.name == SHIM_NAME:
            continue
        text = source.read_text()
        for label, pattern in checks:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{source}:{line}: {label}: {match.group(0)}")

    webkit = core / "OpenAIWeb/OpenAIDashboardWebsiteDataStore.swift"
    if webkit.exists():
        text = webkit.read_text()
        if "WKWebsiteDataStore(forIdentifier: id)" in text and "if #available(macOS 14.0, *)" not in text:
            failures.append(f"{webkit}: unguarded WKWebsiteDataStore(forIdentifier:)")

    if failures:
        details = "\n".join(failures)
        raise SystemExit(
            "Monterey compatibility scan failed; macOS 13/14 API remained after patching:\n" + details)
    print("Monterey compatibility scan passed: no known macOS 13/14-only APIs remain.")


def apply_monterey_source_compat(codexbar: Path, project_root: Path) -> None:
    core = codexbar / CORE_RELATIVE
    if not core.is_dir():
        raise SystemExit(f"CodexBarCore source directory not found: {core}")

    changed_files = 0
    total_changes = 0
    for source in sorted(core.rglob("*.swift")):
        if source.name == SHIM_NAME:
            continue
        relative = source.relative_to(core)
        original = source.read_text()
        updated, changes = transform_core_source(relative, original)
        if updated != original:
            source.write_text(updated)
            changed_files += 1
            total_changes += changes

    shim_source = project_root / "Patches" / SHIM_NAME
    if not shim_source.exists():
        raise SystemExit(f"Monterey compatibility shim not found: {shim_source}")
    shutil.copy2(shim_source, core / SHIM_NAME)

    # A fixed upstream tag must contain these APIs; zero changes means the patch
    # silently stopped matching and should never proceed to a misleading build.
    if changed_files == 0 or total_changes == 0:
        raise SystemExit("No CodexBarCore Monterey source transformations were applied")

    print(
        f"Backported CodexBarCore for macOS 12: {total_changes} source transformation(s) "
        f"across {changed_files} file(s), plus {SHIM_NAME}.")
    scan_for_unavailable_apis(core)


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

    # Apply the deterministic source backport before any optional hand-written
    # patches. The compatibility scan prevents another build from reaching Swift
    # compilation with one of the APIs already exposed by the downloaded CI log.
    apply_monterey_source_compat(codexbar, project_root)

    patch_dir = project_root / "Patches"
    apply_optional_patch(codexbar, patch_dir / "CodexBar.patch")
    apply_optional_patch(sweet, patch_dir / "SweetCookieKit.patch")
    apply_optional_patch(commander, patch_dir / "Commander.patch")


if __name__ == "__main__":
    main()
