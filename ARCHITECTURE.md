# Architecture

## Compatibility boundary

- Upstream owns every provider descriptor, fetch strategy, parser, cookie importer, OAuth/API/CLI probe, cost scan, config schema, and JSON contract.
- This repository owns only the macOS 12 menu UI, settings facade, login item fallback, package assembly, and update feed.
- The UI never calls provider endpoints directly. It launches the bundled `CodexBarCLI` and decodes its JSON.

## Versioning invariant

A release contains one pinned upstream tag from `ENGINE_VERSION`. The shell and helper are packaged and updated together. Never auto-update the helper independently because that can change the JSON schema underneath a running UI.

## Upstream synchronization

1. Scheduled workflow reads the latest upstream GitHub release.
2. It updates `ENGINE_VERSION` in a PR.
3. CI clones that exact tag and the exact SweetCookieKit and Commander versions.
4. CI patches deployment manifests to macOS 12 and builds both architectures.
5. `vtool -show-build` must report `minos 12.0` for the app and helper.
6. A maintainer merges only after macOS 12 smoke tests pass.


## Release/update pipeline

A release tag builds one universal bundle containing the exact shell and engine versions, publishes the ZIP, signs the archive metadata with Sparkle EdDSA, and updates the HTTPS appcast. The private key is provided through standard input in CI and is never written into the repository.
