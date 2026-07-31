#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/Scripts/provider_auth_config_regression.swift" "$TMP/main.swift"
swiftc \
  "$ROOT/Sources/CodexBarMonterey/ProviderAuthentication.swift" \
  "$ROOT/Sources/CodexBarMonterey/CodexBarConfigStore.swift" \
  "$ROOT/Sources/CodexBarMonterey/Models.swift" \
  "$TMP/main.swift" \
  -o "$TMP/provider-auth-regression"

"$TMP/provider-auth-regression"
