#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("patch_upstream", ROOT / "Scripts" / "patch_upstream.py")
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


def write(core: Path, relative: str, text: str) -> None:
    target = core / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        project = Path(temp)
        codexbar = project / "Vendor" / "CodexBar"
        core = codexbar / "Sources" / "CodexBarCore"

        write(core, "Basic.swift", '''import Foundation
final class Box {
    private let lock = OSAllocatedUnfairLock<Int>(initialState: 0)
    let timeout: Duration = .seconds(1)
    let now: ContinuousClock.Instant = ContinuousClock.now
    func run() async throws { try await Task.sleep(for: .milliseconds(20)) }
    func urls(_ url: URL) {
        _ = url.host(percentEncoded: false)
        _ = url.appending(queryItems: [URLQueryItem(name: "x", value: "1")])
        _ = url.appending(path: "api/test")
        var copy = url
        copy.append(path: "quota")
        _ = "a::b".split(separator: "::")
        _ = ".host".trimmingPrefix(".")
        _ = TimeZone(secondsFromGMT: 0) ?? .gmt
    }
}
''')
        write(core, "Providers/Codex/CodexStatusProbe.swift", '''import Foundation
func parse(_ value: String) {
    var raw = value
    if let match = raw.firstMatch(of: /^([0-9]{1,2}:[0-9]{2}) on ([0-9]{1,2} [A-Za-z]{3})$/) {
        raw = "\\(match.output.2) \\(match.output.1)"
    }
    if let match = raw.firstMatch(of: /^([0-9]{1,2}:[0-9]{2}) on ([A-Za-z]{3} [0-9]{1,2})$/) {
        raw = "\\(match.output.2) \\(match.output.1)"
    }
}
''')
        write(core, "Providers/Doubao/DoubaoUsageFetcher.swift", '''import Foundation
func parse(_ trimmed: String) {
        let pattern = /(\\d+)([dhms])/
        for match in trimmed.matches(of: pattern) {
            guard let num = Double(match.1) else { continue }
            switch match.2 {
            case "d": _ = num
            default: break
            }
        }
}
''')
        write(core, "Providers/Kiro/KiroStatusProbe.swift", '''import Foundation
func parse(_ creditsStr: String, _ bonusStr: String) {
    let numbers = creditsStr.matches(of: /(\\d+\\.?\\d*)/)
    _ = Double(String(numbers[0].output.1))
    _ = Double(String(numbers[1].output.1))
    let numbers = bonusStr.matches(of: /(\\d+\\.?\\d*)/)
    _ = Double(String(numbers[0].output.1))
    _ = Double(String(numbers[1].output.1))
}
''')
        write(core, "OpenAIWeb/OpenAIDashboardWebsiteDataStore.swift", '''import WebKit
func store(storageKey: String) -> WKWebsiteDataStore {
        let id = Self.identifier(forStorageKey: storageKey)
        let store = WKWebsiteDataStore(forIdentifier: id)
        self.cachedStores[storageKey] = store
        return store
}
''')

        module.apply_monterey_source_compat(codexbar, ROOT)
        module.scan_for_unavailable_apis(core)

        basic = (core / "Basic.swift").read_text()
        assert "MontereyDuration" in basic
        assert "MontereyContinuousClock" in basic
        assert "MontereyStateLock" in basic
        assert ".montereyHost(percentEncoded:" in basic
        assert ".montereyAppending(queryItems:" in basic
        assert ".appendingPathComponent(" in basic
        assert ".appendPathComponent(" in basic
        assert ".montereySplit(separator:" in basic
        assert ".montereyTrimmingPrefix(" in basic
        assert "TimeZone(secondsFromGMT: 0)!" in basic

        codex = (core / "Providers/Codex/CodexStatusProbe.swift").read_text()
        assert "montereyFirstRegexCaptures" in codex and "match[2]" in codex
        doubao = (core / "Providers/Doubao/DoubaoUsageFetcher.swift").read_text()
        assert "montereyRegexCaptures" in doubao and "match[1]" in doubao
        kiro = (core / "Providers/Kiro/KiroStatusProbe.swift").read_text()
        assert kiro.count("montereyRegexCaptures") == 2
        assert ".output.1" not in kiro
        webkit = (core / "OpenAIWeb/OpenAIDashboardWebsiteDataStore.swift").read_text()
        assert "if #available(macOS 14.0, *)" in webkit
        assert "store = .default()" in webkit
        assert (core / "MontereyCompat.swift").exists()

    print("Monterey patcher synthetic regression test passed.")


if __name__ == "__main__":
    main()
