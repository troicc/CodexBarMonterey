#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/universal/CodexBar Monterey.app"
[[ -d "$APP" ]] || "$ROOT/Scripts/build_universal.sh"
rm -rf "/Applications/CodexBar Monterey.app"
ditto "$APP" "/Applications/CodexBar Monterey.app"
open "/Applications/CodexBar Monterey.app"
