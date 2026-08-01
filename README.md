# CodexBar Monterey Full

A macOS 12 compatibility shell that preserves CodexBar's complete upstream provider engine and whole-bundle Sparkle updates.

The project pins an upstream CodexBar release in `ENGINE_VERSION`, builds its shared `CodexBarCore + CodexBarCLI`, embeds the CLI as the provider engine, and replaces only the macOS 14 UI layer with AppKit compatible with Monterey.

Included:

- all providers registered by the pinned upstream tag;
- upstream browser-cookie, CLI/RPC/PTY, OAuth, API-key, cloud-credential, local-file/database, cost, and status paths;
- provider enable/disable, API-key, cookie refresh, and cache controls;
- merged or per-provider menu-bar presentation;
- compact graphical provider dashboards backed by upstream CLI JSON;
- native macOS shortcuts, application/context menus, scrolling, and VoiceOver labels;
- account-isolated local quota/spend history and transactional credential verification;
- universal arm64/x86_64 packaging;
- Sparkle 2.9.4 signed appcast releases;
- optional Developer ID signing and notarization;
- daily upstream release PRs and macOS 12 deployment-target verification.

Provider-specific raw output remains available through the bundled CLI. The app does not port WidgetKit, every bespoke animation, or every provider-specific login surface, and does not claim pixel-perfect parity with the macOS 14+ upstream UI.

GitHub Actions runs behavioral Swift tests, Monterey backport regressions, release-contract checks, and recursive Universal 2 validation. Swift 5.6 machines can still run the lightweight parser, history, authentication, and patcher regressions without building the full Swift 6.2 package.

See [README.zh-CN.md](README.zh-CN.md) for the complete setup and release guide.
