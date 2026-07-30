#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${CODEXBAR_MONTEREY_ENV:-$ROOT/Config/build.env}"
[[ -f "$ENV_FILE" ]] || { echo "Copy Config/build.env.example to Config/build.env first." >&2; exit 1; }
# Explicit CI/shell values override the local config file.
ENV_CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY-}"
# Export build settings so the Info.plist rendering subprocess sees them.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
if [[ -n "$ENV_CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$ENV_CODE_SIGN_IDENTITY"
fi
ARCH="${1:-$(uname -m)}"
export MACOSX_DEPLOYMENT_TARGET=12.0
swift build --package-path "$ROOT" -c release --arch "$ARCH" --product CodexBarMonterey
APP_BIN_DIR="$(swift build --package-path "$ROOT" -c release --arch "$ARCH" --show-bin-path)"
APPBIN="$APP_BIN_DIR/CodexBarMonterey"
[[ -x "$APPBIN" ]] || { echo "App build output not found: $APPBIN" >&2; exit 1; }
ENGINE="$ROOT/build/engine/$ARCH/CodexBarCLI"
[[ -x "$ENGINE" ]] || "$ROOT/Scripts/build_engine.sh" "$ARCH"

APP="$ROOT/dist/$ARCH/CodexBar Monterey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$APPBIN" "$APP/Contents/MacOS/CodexBarMonterey"
cp "$ENGINE" "$APP/Contents/Helpers/CodexBarCLI"

SPARKLE_SEARCH_ROOT="$ROOT/.build"
SPARKLE="$(find "$SPARKLE_SEARCH_ROOT" -path '*/Sparkle.framework' -type d | head -1 || true)"
[[ -n "$SPARKLE" ]] || { echo "Sparkle.framework not found under $SPARKLE_SEARCH_ROOT" >&2; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

python3 - "$ROOT/Resources/Info.plist.template" "$APP/Contents/Info.plist" <<'PY'
from pathlib import Path
import os, sys
source, target = map(Path, sys.argv[1:])
text = source.read_text()
values = {
    "__BUNDLE_ID__": os.environ["BUNDLE_ID"],
    "__VERSION__": os.environ["APP_VERSION"],
    "__BUILD__": os.environ["BUILD_NUMBER"],
    "__APPCAST_URL__": os.environ["APPCAST_URL"],
    "__SPARKLE_PUBLIC_KEY__": os.environ["SPARKLE_PUBLIC_KEY"],
}
for key, value in values.items(): text = text.replace(key, value)
target.write_text(text)
PY

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/CodexBarMonterey" 2>/dev/null || true
"$ROOT/Scripts/sign_app.sh" "$APP"
echo "$APP"
