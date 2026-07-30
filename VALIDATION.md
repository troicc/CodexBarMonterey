# Validation record

Date: 2026-07-30

Completed in the delivery environment:

- shell syntax check for every script;
- Python bytecode compilation for the patch/update scripts;
- Swift package manifest evaluation with macOS 12 and Sparkle 2.9.4 assertions;
- syntax parsing for every AppKit Swift source file;
- portable type checking for the provider JSON model and CLI process client;
- GitHub Actions YAML parsing;
- 65-ID v0.46.0 fallback provider registry count/uniqueness check;
- synthetic manifest patch test covering CodexBar, SweetCookieKit, and Commander;
- generated-directory and secret-file cleanup check.

Not possible in this Linux delivery environment:

- linking AppKit or Sparkle;
- cloning and compiling the full upstream provider engine;
- code signing, notarization, or appcast generation;
- macOS 12 runtime, browser-cookie, Keychain, provider-authentication, or Sparkle upgrade tests.

Those checks are explicit gates in the included macOS 26 GitHub Actions workflows and
`Scripts/smoke_test_app.sh`. A release should not be treated as verified for Monterey until the
workflow succeeds and the app is exercised on both Intel and Apple Silicon macOS 12.6.x.

## 2026-07-30 real GitHub Actions failure remediation

The first public build reached Swift compilation successfully, then reported 221
availability diagnostics across 42 `CodexBarCore` files. The failure was not the
Node.js Actions warning. The source engine still used APIs introduced in macOS
13/14 after only its package deployment declaration had been lowered.

This revision adds a deterministic source backport performed by
`Scripts/patch_upstream.py` after the fixed upstream tag is fetched:

- Swift `Duration` / `ContinuousClock` are replaced by the Foundation-backed
  `MontereyDuration` / `MontereyContinuousClock` compatibility types.
- `OSAllocatedUnfairLock` is replaced by an `NSLock`-backed state lock.
- Swift Regex call sites are converted to `NSRegularExpression` helpers.
- macOS 13 URL, String, and TimeZone convenience APIs use older equivalents.
- the macOS 14 per-identifier WebKit store is availability-guarded, with a
  persistent default-store fallback on Monterey.
- a post-patch source scan fails immediately if any known unavailable call site
  remains.

Validation added in this revision:

- synthetic regression coverage for every unavailable API family in the log;
- Swift type checking of `Patches/MontereyCompat.swift`;
- Python syntax checks and shell syntax checks;
- Node 24-compatible GitHub Actions versions retained.

A true AppKit/SwiftPM link and a macOS 12 runtime launch still require the macOS
GitHub runner and Monterey hardware respectively; those cannot be honestly
claimed from a Linux validation environment.

## CompilerFix2: Wayfinder path rewrite regression

The second GitHub Actions log reached `CodexBarCore` compilation after the macOS 12 availability backport, then failed because a global replacement changed the valid helper call
`WayfinderSettingsReader.appending(path:to:)` into `self.appendingPathComponent(..., to: ...)`.

CompilerFix2 removes global `appending(path:)` / `append(path:)` rewrites. It pins those conversions to the three v0.46.0 files that actually use the macOS 13 URL path APIs (Devin, ElevenLabs, and NeuralWatt), preserves Wayfinder's helper method, scans for the invalid `to:` rewrite, and type-checks transformed regression fixtures with `swiftc`.

## CompilerFix3: CodexBarCLI clock backport

The third GitHub Actions log confirmed that `CodexBarCore` now compiles and the
build advances to the `CodexBarCLI` target. It then reported 40 compiler
diagnostics, all in two files:

- `Sources/CodexBarCLI/CLIServeCommand.swift`
- `Sources/CodexBarCLI/CLIServeOperationCoordinator.swift`

Every diagnostic belongs to the same macOS 13 clock API family:
`ContinuousClock`, `ContinuousClock.Instant`, `now`, `advanced(by:)`,
`Duration.seconds`, `sleep(until:)`, and `Instant: Comparable`.

CompilerFix3 expands the deterministic source transform and compatibility scan
from `CodexBarCore` to both build targets (`CodexBarCore` and `CodexBarCLI`).
Transformed CLI files receive an explicit file-scoped `import CodexBarCore`
when needed. `MontereyContinuousClock` now implements `sleep(until:)`.

The regression suite now builds the compatibility shim as a real
`CodexBarCore.swiftmodule`, imports it from synthetic CLI files, and type-checks
the exact clock operations used by the failed upstream files: optional
deadlines, `now`, `advanced(by: .seconds(...))`, `min`, comparison operators,
and asynchronous `sleep(until:)`.

## CompilerFix4: Swift 6.3 AppKit entry point

- Replaced top-level `main.swift` statements with an explicit `@main` entry type.
- Marked `static main()` as `@MainActor`, so constructing `AppDelegate` and accessing AppKit satisfy Swift 6.3 actor isolation.
- Retained the delegate across the blocking AppKit run loop using `withExtendedLifetime`.
- Added a fast `Preflight menu app target` workflow step before the provider engine build.
- Reordered `build_universal.sh` so the lightweight AppKit target compiles before the expensive upstream engine for each architecture.
- Compiled the exact `CodexBarMontereyApp.swift` and `AppDelegate.swift` against a synthetic actor-annotated AppKit module under Swift 6.2; the previous MainActor isolation error no longer reproduces.
