#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /private/tmp/codexbar-model-visual.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
OUTPUT="${1:-$ROOT/artifacts/model-attribution-visual}"
SOURCES=()
for source in "$ROOT"/Sources/CodexBarMonterey/*.swift; do
  [[ "$(basename "$source")" == "CodexBarMontereyApp.swift" ]] && continue
  SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$TMP/module-cache" \
  "${SOURCES[@]}" "$ROOT/Scripts/visual_model_attribution.swift" -o "$TMP/visual-qa"
"$TMP/visual-qa" "$OUTPUT"
