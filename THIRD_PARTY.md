# Third-party components

This compatibility shell does not vendor third-party source in the repository.
The build downloads pinned upstream releases and must preserve their licenses.

- **CodexBar / CodexBarCore / CodexBarCLI** — fetched from the tag in
  `ENGINE_VERSION`; see the upstream repository for its license and notices.
- **SweetCookieKit** — the exact version referenced by that CodexBar tag is
  fetched and patched locally only to lower the declared deployment target and,
  when required, apply an explicit source compatibility patch.
- **Commander** — the exact version referenced by the pinned CodexBar tag is fetched, redirected to a local checkout, and patched only for the Monterey deployment target.
- **Sparkle 2.9.4** — linked through Swift Package Manager and distributed in
  the application bundle; preserve Sparkle's license and acknowledgements.

Before public distribution, review the license files in `Vendor/CodexBar`,
`Vendor/SweetCookieKit`, `Vendor/Commander`, and SwiftPM's checked-out Sparkle package and include
all notices required by those licenses in the release bundle or repository.
