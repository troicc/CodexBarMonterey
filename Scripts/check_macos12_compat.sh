#!/usr/bin/env bash
set -euo pipefail
APP="${1:?Usage: check_macos12_compat.sh /path/to/App.app}"
[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }

fail=0
while IFS= read -r -d '' candidate; do
  if file "$candidate" | grep -q 'Mach-O'; then
    echo "== $candidate =="
    output="$(xcrun vtool -show-build "$candidate" 2>&1 || true)"
    echo "$output" | grep -E 'platform|sdk|minos' || true
    if ! python3 - "$candidate" "$output" <<'PY'
import re, sys
path, output = sys.argv[1], sys.argv[2]
versions = re.findall(r'\bminos\s+([0-9]+(?:\.[0-9]+){0,2})', output)
if not versions:
    print(f"No LC_BUILD_VERSION minos found for {path}", file=sys.stderr)
    raise SystemExit(1)
for version in versions:
    parts = tuple(int(x) for x in version.split('.'))
    if parts > (12, 99, 99):
        print(f"Incompatible minimum OS {version}: {path}", file=sys.stderr)
        raise SystemExit(1)
PY
    then
      fail=1
    fi
  fi
done < <(find "$APP" -type f -print0)

MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
[[ "$MIN_OS" == "12.0" ]] || { echo "LSMinimumSystemVersion is $MIN_OS, expected 12.0" >&2; fail=1; }
codesign --verify --deep --strict --verbose=2 "$APP"
exit "$fail"
