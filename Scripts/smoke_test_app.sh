#!/usr/bin/env bash
set -euo pipefail

APP="${1:-/Applications/CodexBar Monterey.app}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }

MAIN="$APP/Contents/MacOS/CodexBarMonterey"
HELPER="$APP/Contents/Helpers/CodexBarCLI"
[[ -x "$MAIN" ]] || { echo "Main executable missing: $MAIN" >&2; exit 1; }
[[ -x "$HELPER" ]] || { echo "CLI helper missing: $HELPER" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_CONFIG_DIR=""
cleanup() {
  if [[ -n "$TEMP_CONFIG_DIR" && -d "$TEMP_CONFIG_DIR" ]]; then
    rm -rf "$TEMP_CONFIG_DIR"
  fi
}
trap cleanup EXIT

echo "== Host =="
sw_vers
uname -m

echo "== Bundle =="
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Architectures =="
for binary in "$MAIN" "$HELPER"; do
  printf '%s: ' "$binary"
  lipo -archs "$binary"
done

echo "== Deployment targets =="
"$SCRIPT_DIR/check_macos12_compat.sh" "$APP"

echo "== Provider engine =="
"$HELPER" --version
PROVIDERS_JSON="$("$HELPER" config providers --json)"
printf '%s\n' "$PROVIDERS_JSON"
python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
rows = data if isinstance(data, list) else data.get("providers", []) if isinstance(data, dict) else None
assert isinstance(rows, list), "provider catalog must contain a JSON array"
assert rows, "provider catalog must not be empty"
' <<<"$PROVIDERS_JSON"

if [[ "${CODEXBAR_SMOKE_OFFLINE:-0}" == "1" ]]; then
  echo "== Offline enabled-provider probe =="
  TEMP_CONFIG_DIR="$(mktemp -d)"
  export CODEXBAR_CONFIG="$TEMP_CONFIG_DIR/config.json"
  printf '{}\n' > "$CODEXBAR_CONFIG"
  chmod 600 "$CODEXBAR_CONFIG"

  while IFS= read -r provider_id; do
    [[ -n "$provider_id" ]] || continue
    "$HELPER" config disable --provider "$provider_id" >/dev/null
  done < <(python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
rows = data if isinstance(data, list) else data.get("providers", []) if isinstance(data, dict) else []
for item in rows:
    provider_id = item.get("id") if isinstance(item, dict) else None
    if provider_id:
        print(provider_id)
' <<<"$PROVIDERS_JSON")
else
  echo "== Enabled-provider probe =="
fi

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

if [[ "${CODEXBAR_SMOKE_OFFLINE:-0}" == "1" && "$STATUS" -ne 0 ]]; then
  echo "Offline provider probe failed with exit $STATUS." >&2
  exit "$STATUS"
fi

echo "Smoke test completed. Online provider-specific authentication errors may still require configuration in the app."
