#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: sign_app.sh /path/to/App.app}"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }

BASE_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  BASE_ARGS+=(--options runtime --timestamp)
  if [[ -n "${CODE_SIGN_KEYCHAIN:-}" ]]; then
    BASE_ARGS+=(--keychain "$CODE_SIGN_KEYCHAIN")
  fi
fi

sign_one() {
  local item="$1"
  shift
  [[ -e "$item" ]] || return 0
  codesign "${BASE_ARGS[@]}" "$@" "$item"
}

# The app is not sandboxed, but the prebuilt Sparkle framework still contains
# nested updater/XPC code. Re-sign in Sparkle's documented inside-out order.
# Downloader.xpc carries an entitlement that must survive manual re-signing.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  VERSION_ROOT="$SPARKLE/Versions/B"
  sign_one "$VERSION_ROOT/XPCServices/Installer.xpc"
  sign_one "$VERSION_ROOT/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
  sign_one "$VERSION_ROOT/Autoupdate"
  sign_one "$VERSION_ROOT/Updater.app"
  sign_one "$SPARKLE"
fi

# Sign bundled non-framework helpers before the outer application.
while IFS= read -r -d '' helper; do
  [[ -L "$helper" ]] && continue
  if file "$helper" | grep -q 'Mach-O'; then
    sign_one "$helper"
  fi
done < <(find "$APP/Contents/Helpers" -type f -print0 2>/dev/null || true)

sign_one "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
