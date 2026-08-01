#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT/ENGINE_VERSION")}" 
VENDOR="$ROOT/Vendor"
rm -rf "$VENDOR"
mkdir -p "$VENDOR"

git clone --depth 1 --branch "$VERSION" https://github.com/steipete/CodexBar.git "$VENDOR/CodexBar"

SWEETCOOKIEKIT_VERSION="$(python3 - "$VENDOR/CodexBar/Package.swift" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
patterns = [
    r'name:\s*"SweetCookieKit"[\s\S]{0,300}?from:\s*"([^"]+)"',
    r'github\.com/steipete/SweetCookieKit(?:\.git)?"\s*,\s*(?:exact|from):\s*"([^"]+)"',
]
for pattern in patterns:
    match = re.search(pattern, text)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit("Could not determine SweetCookieKit version from upstream Package.swift")
PY
)"

clone_tag() {
  local repository="$1"
  local version="$2"
  local destination="$3"
  if git clone --depth 1 --branch "$version" "$repository" "$destination"; then
    return 0
  fi
  rm -rf "$destination"
  git clone --depth 1 --branch "v$version" "$repository" "$destination"
}

clone_tag \
  https://github.com/steipete/SweetCookieKit.git \
  "$SWEETCOOKIEKIT_VERSION" \
  "$VENDOR/SweetCookieKit"

COMMANDER_VERSION="$(python3 - "$VENDOR/CodexBar/Package.swift" <<'PY_COMMANDER'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
patterns = [
    r'github\.com/steipete/Commander(?:\.git)?"\s*,\s*(?:exact|from):\s*"([^"]+)"',
]
for pattern in patterns:
    match = re.search(pattern, text)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit("Could not determine Commander version from upstream Package.swift")
PY_COMMANDER
)"

clone_tag \
  https://github.com/steipete/Commander.git \
  "$COMMANDER_VERSION" \
  "$VENDOR/Commander"

python3 "$ROOT/Scripts/patch_upstream.py" "$VENDOR/CodexBar"
printf '%s\n' "$VERSION" > "$VENDOR/.engine-version"
python3 "$ROOT/Scripts/engine_source_fingerprint.py" > "$VENDOR/.source-fingerprint"

# Force the upstream package to use the patched local cookie library.
export CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT=1
export MACOSX_DEPLOYMENT_TARGET=12.0

printf 'Fetched CodexBar engine %s with SweetCookieKit %s, Commander %s, and applied Monterey manifest and source compatibility patches.\n' \
  "$VERSION" "$SWEETCOOKIEKIT_VERSION" "$COMMANDER_VERSION"
