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
