# Upstream Monterey compatibility layer

The build performs deterministic compatibility work after cloning the fixed
upstream engine version:

1. CodexBar, SweetCookieKit, and Commander deployment targets are lowered to
   macOS 12.
2. CodexBar is redirected to the exact vendored Commander checkout.
3. `Scripts/patch_upstream.py` rewrites the macOS 13/14-only API families found
   by the real GitHub Actions compiler log and installs `MontereyCompat.swift`.
4. A deny-list scanner fails the build if any known unavailable call site
   remains after rewriting.

`MontereyCompat.swift` contains the back-deployed clock/duration, lock, URL,
String, and regular-expression helpers. Keep it dependency-free and compatible
with the macOS 12 SDK.

Optional ordinary patches may still be added here for changes that cannot be
expressed safely by the deterministic transformer:

- `CodexBar.patch`
- `SweetCookieKit.patch`
- `Commander.patch`

The build checks each optional patch with `git apply --check` before applying
it. Do not modify `Vendor/` manually because it is recreated for every clean
build.
