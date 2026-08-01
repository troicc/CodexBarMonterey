#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT/ENGINE_VERSION")"
EXPECTED_FINGERPRINT="$(python3 "$ROOT/Scripts/engine_source_fingerprint.py")"
INSTALLED_VERSION="$(cat "$ROOT/Vendor/.engine-version" 2>/dev/null || true)"
INSTALLED_FINGERPRINT="$(cat "$ROOT/Vendor/.source-fingerprint" 2>/dev/null || true)"
if [[ ! -d "$ROOT/Vendor/CodexBar" ||
      "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ||
      "$INSTALLED_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]]; then
  echo "Provider engine source inputs changed; refreshing the pinned vendor tree."
  "$ROOT/Scripts/fetch_engine.sh"
fi
export CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT=1
export MACOSX_DEPLOYMENT_TARGET=12.0
swift build --package-path "$ROOT/Vendor/CodexBar" -c release --arch "$ARCH" --product CodexBarCLI
BIN_DIR="$(swift build --package-path "$ROOT/Vendor/CodexBar" -c release --arch "$ARCH" --show-bin-path)"
BIN="$BIN_DIR/CodexBarCLI"
[[ -x "$BIN" ]] || { echo "CodexBarCLI build output not found: $BIN" >&2; exit 1; }
mkdir -p "$ROOT/build/engine/$ARCH"
cp "$BIN" "$ROOT/build/engine/$ARCH/CodexBarCLI"
chmod +x "$ROOT/build/engine/$ARCH/CodexBarCLI"
