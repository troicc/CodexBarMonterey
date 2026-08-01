#!/usr/bin/env bash
set -euo pipefail

APP="${1:-/Applications/CodexBar Monterey.app}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }

MAIN="$APP/Contents/MacOS/CodexBarMonterey"
HELPER="$APP/Contents/Helpers/CodexBarCLI"
[[ -x "$MAIN" ]] || { echo "Main executable missing: $MAIN" >&2; exit 1; }
[[ -x "$HELPER" ]] || { echo "CLI helper missing: $HELPER" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Host =="
sw_vers
uname -m

echo "== Bundle =="
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Architectures =="
mach_o_count=0
while IFS= read -r -d '' binary; do
  file "$binary" | grep -q 'Mach-O' || continue
  mach_o_count=$((mach_o_count + 1))
  archs="$(lipo -archs "$binary")"
  printf '%s: %s\n' "${binary#"$APP/"}" "$archs"
  if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
    echo "Bundle contains a non-universal Mach-O component: $binary" >&2
    exit 1
  fi
done < <(find "$APP" -type f -print0)
[[ "$mach_o_count" -gt 0 ]] || { echo "Bundle contains no Mach-O files." >&2; exit 1; }

echo "== Deployment targets =="
"$SCRIPT_DIR/check_macos12_compat.sh" "$APP"

echo "== Provider engine =="
"$HELPER" --version
PROVIDERS_JSON="$("$HELPER" config providers --json)"
printf '%s\n' "$PROVIDERS_JSON"
PROVIDER_COUNT="$(printf '%s\n' "$PROVIDERS_JSON" | python3 "$SCRIPT_DIR/validate_provider_catalog.py" --min-count 60)"
echo "Validated $PROVIDER_COUNT registered providers."

if [[ "${CODEXBAR_SMOKE_OFFLINE:-0}" == "1" ]]; then
  echo "== Offline provider probe =="
  echo "Skipped live usage fetching: the clean CI runner intentionally has no provider credentials, browser sessions, or provider CLIs."
  echo "The provider registry, CLI executable, bundle signing, architectures, and deployment targets were validated offline."
else
  echo "== Enabled-provider probe =="
  set +e
  OUTPUT="$("$HELPER" --format json --json-only --status 2>&1)"
  STATUS=$?
  set -e
  printf '%s\n' "$OUTPUT"

  if [[ -z "${OUTPUT//[[:space:]]/}" ]]; then
    echo "Provider probe produced no output (exit $STATUS)." >&2
    exit 1
  fi

  python3 -c '
import json, sys
text = sys.stdin.read().strip()
try:
    json.loads(text)
except json.JSONDecodeError as exc:
    print(f"Provider probe was not valid JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)
' <<<"$OUTPUT"

  if [[ "$STATUS" -ne 0 ]]; then
    echo "Live provider probe failed with exit $STATUS." >&2
    exit "$STATUS"
  fi
fi

echo "Smoke test completed successfully."
