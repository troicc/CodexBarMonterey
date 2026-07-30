# CodexBar Monterey Full

A macOS 12 compatibility shell that preserves CodexBar's complete upstream provider engine and whole-bundle Sparkle updates.

The project pins an upstream CodexBar release in `ENGINE_VERSION`, builds its shared `CodexBarCore + CodexBarCLI`, embeds the CLI as the provider engine, and replaces only the macOS 14 UI layer with AppKit compatible with Monterey.

Included:

- all providers registered by the pinned upstream tag;
- upstream browser-cookie, CLI/RPC/PTY, OAuth, API-key, cloud-credential, local-file/database, cost, and status paths;
- provider enable/disable, API-key, cookie refresh, and cache controls;
- merged or per-provider menu-bar presentation;
- provider-native detail rendering through the upstream CLI;
- universal arm64/x86_64 packaging;
- Sparkle 2.9.4 signed appcast releases;
- optional Developer ID signing and notarization;
- daily upstream release PRs and macOS 12 deployment-target verification.

This does not port the original SwiftUI settings views, WidgetKit extension, bespoke animations, or every provider-specific login surface. It preserves the provider data plane and update behavior rather than claiming pixel-perfect UI parity.

See [README.zh-CN.md](README.zh-CN.md) for the complete setup and release guide.
