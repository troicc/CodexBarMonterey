#!/usr/bin/env bash
set -euo pipefail

: "${DEVELOPER_ID_P12_BASE64:?Set DEVELOPER_ID_P12_BASE64}"
: "${DEVELOPER_ID_P12_PASSWORD:?Set DEVELOPER_ID_P12_PASSWORD}"
: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY}"

WORK_ROOT="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN_PATH="$WORK_ROOT/codexbar-signing.keychain-db"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -hex 24)}"
CERTIFICATE_PATH="$WORK_ROOT/codexbar-developer-id.p12"

printf '%s' "$DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$CERTIFICATE_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$DEVELOPER_ID_P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
security find-identity -v -p codesigning "$KEYCHAIN_PATH"
rm -f "$CERTIFICATE_PATH"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'CODE_SIGN_IDENTITY=%s\n' "$CODE_SIGN_IDENTITY" >> "$GITHUB_ENV"
  printf 'CODE_SIGN_KEYCHAIN=%s\n' "$KEYCHAIN_PATH" >> "$GITHUB_ENV"
fi
