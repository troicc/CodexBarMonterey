#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Scripts/cost_history_parser_regression.swift" "$TMP/main.swift"
swiftc \
  "$ROOT/Sources/CodexBarMonterey/CostHistoryPayload.swift" \
  "$TMP/main.swift" \
  -o "$TMP/cost-history-regression"
"$TMP/cost-history-regression"
