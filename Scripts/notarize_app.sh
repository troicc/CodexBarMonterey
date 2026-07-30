#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: notarize_app.sh /path/to/App.app /path/to/release.zip}"
RELEASE_ZIP="${2:?Usage: notarize_app.sh /path/to/App.app /path/to/release.zip}"
: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}"

[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }
TMP_ZIP="$(mktemp -t codexbar-notary).zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$TMP_ZIP"

xcrun notarytool submit "$TMP_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$RELEASE_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_ZIP"
rm -f "$TMP_ZIP"
echo "$RELEASE_ZIP"
