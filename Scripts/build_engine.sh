#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
[[ -d "$ROOT/Vendor/CodexBar" ]] || "$ROOT/Scripts/fetch_engine.sh"
export CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT=1
export MACOSX_DEPLOYMENT_TARGET=12.0
swift build --package-path "$ROOT/Vendor/CodexBar" -c release --arch "$ARCH" --product CodexBarCLI
BIN_DIR="$(swift build --package-path "$ROOT/Vendor/CodexBar" -c release --arch "$ARCH" --show-bin-path)"
BIN="$BIN_DIR/CodexBarCLI"
[[ -x "$BIN" ]] || { echo "CodexBarCLI build output not found: $BIN" >&2; exit 1; }
mkdir -p "$ROOT/build/engine/$ARCH"
cp "$BIN" "$ROOT/build/engine/$ARCH/CodexBarCLI"
chmod +x "$ROOT/build/engine/$ARCH/CodexBarCLI"
