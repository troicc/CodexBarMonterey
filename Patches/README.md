# Upstream compatibility patches

The build always performs three deterministic manifest edits before compiling:

1. CodexBar's deployment target is lowered to macOS 12.
2. SweetCookieKit's deployment target is lowered to macOS 12.
3. Commander is vendored at the exact version requested by CodexBar, redirected to a local package, and lowered from its declared macOS 14 target to macOS 12.

If a newer upstream release starts using APIs unavailable on Monterey, add ordinary `git apply` patches here:

- `CodexBar.patch`
- `SweetCookieKit.patch`
- `Commander.patch`

The build checks each patch with `git apply --check` before applying it. Keep patches versioned and narrow; do not modify `Vendor/` manually because it is recreated for every build.
