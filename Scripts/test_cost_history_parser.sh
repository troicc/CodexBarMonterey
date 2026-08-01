#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MODULE_CACHE="$TMP/module-cache"
mkdir -p "$MODULE_CACHE"

cp "$ROOT/Scripts/cost_history_parser_regression.swift" "$TMP/main.swift"
swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Sources/CodexBarMonterey/CostHistoryPayload.swift" \
  "$TMP/main.swift" \
  -o "$TMP/cost-history-regression"
"$TMP/cost-history-regression"

cp "$ROOT/Scripts/quota_trend_store_regression.swift" "$TMP/main.swift"
swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Sources/CodexBarMonterey/Models.swift" \
  "$ROOT/Sources/CodexBarMonterey/LocalQuotaTrendStore.swift" \
  "$TMP/main.swift" \
  -o "$TMP/quota-trend-regression"
"$TMP/quota-trend-regression"

cp "$ROOT/Scripts/local_spend_history_regression.swift" "$TMP/main.swift"
swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Sources/CodexBarMonterey/Models.swift" \
  "$ROOT/Sources/CodexBarMonterey/ProviderFinance.swift" \
  "$ROOT/Sources/CodexBarMonterey/LocalSpendHistoryStore.swift" \
  "$TMP/main.swift" \
  -o "$TMP/local-spend-regression"
"$TMP/local-spend-regression"
