# CodexBar Monterey Full

A macOS 12 compatibility shell that preserves CodexBar's complete upstream provider engine and Sparkle-ready whole-bundle packaging.

The project pins an upstream CodexBar release in `ENGINE_VERSION`, builds its shared `CodexBarCore + CodexBarCLI`, embeds the CLI as the provider engine, and replaces only the macOS 14 UI layer with AppKit compatible with Monterey.

Included:

- all providers registered by the pinned upstream tag;
- upstream browser-cookie, CLI/RPC/PTY, OAuth, API-key, cloud-credential, local-file/database, cost, and status paths;
- provider enable/disable, API-key, cookie refresh, and cache controls;
- merged or per-provider menu-bar presentation with four status-item display styles;
- a native macOS status menu with configurable overview rows, provider/account submenus, quota pace, resets, metrics, and service state;
- native, status-item-anchored provider detail popovers with explicit quota labels and separately labeled token/cost history charts;
- Manual, fixed, and adaptive refresh modes, refresh-on-open, transition-based service/quota notifications, and VoiceOver labels;
- account-isolated local quota/spend history, transactional credential verification, and in-app token-account switching/removal;
- z.ai compact views prioritize and label the five-hour allowance while retaining MCP/monthly windows in full details;
- universal arm64/x86_64 packaging;
- Sparkle 2.9.4 integration; a signed update channel still requires a real appcast/key configuration;
- optional Developer ID signing and notarization;
- daily upstream release PRs and macOS 12 deployment-target verification.

Provider-specific raw output remains available through the bundled CLI. The app does not port WidgetKit, every bespoke animation, or every provider-specific login surface, and does not claim pixel-perfect parity with the macOS 14+ upstream UI.

GitHub Actions runs behavioral Swift tests, Monterey backport regressions, release-contract checks, and recursive Universal 2 validation. Swift 5.6 machines can still run the lightweight parser, history, authentication, and patcher regressions without building the full Swift 6.2 package.

## Local UI validation on Swift 5.6

When the machine cannot load the Swift 6.2 package manifest, it can still build the current AppKit/SwiftUI shell directly for both `arm64` and `x86_64`. The script copies `CodexBarCLI`, Sparkle, the bundle identifier, and other resources from an already installed or otherwise validated template app, replaces only the UI executable, ad-hoc signs the result, and runs the recursive offline bundle checks:

```bash
CODEXBAR_LOCAL_TEMPLATE_APP="/Applications/CodexBar Monterey.app" \
CODEXBAR_LOCAL_VERSION="0.10.0" \
Scripts/build_local_validation.sh
```

To exercise the real menu and provider-detail popover before the script exits, quit any running CodexBar instance and add `CODEXBAR_LOCAL_RUN_UI_SMOKE=1`. Install an accepted local bundle with `Scripts/install_local.sh "/absolute/path/to/the.app"`; the installer keeps the previous app in a recoverable `/private/tmp` backup.

This is a UI/interaction validation path, not a release build: the helper and Sparkle framework come from the template, the main executable uses the no-Sparkle fallback, and the bundle is only ad-hoc signed. GitHub Actions or a complete Swift 6.2 local build remains authoritative for the pinned provider engine, Sparkle linkage, and release archive.

See [README.zh-CN.md](README.zh-CN.md) for the complete setup and release guide.
