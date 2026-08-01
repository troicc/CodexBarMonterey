#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-$ROOT/dist/universal/CodexBar Monterey.app}"
TARGET_APP="/Applications/CodexBar Monterey.app"

if [[ "$#" -eq 0 && ! -d "$SOURCE_APP" ]]; then
  "$ROOT/Scripts/build_universal.sh"
fi
[[ -d "$SOURCE_APP" ]] || { echo "Source app not found: $SOURCE_APP" >&2; exit 1; }
[[ "$SOURCE_APP" != "$TARGET_APP" ]] || { echo "Source app is already installed." >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE_APP"

pkill -x CodexBarMonterey 2>/dev/null || true

BACKUP_ROOT=""
BACKUP_APP=""
if [[ -d "$TARGET_APP" ]]; then
  BACKUP_ROOT="$(mktemp -d /private/tmp/codexbar-install-backup.XXXXXX)"
  BACKUP_APP="$BACKUP_ROOT/CodexBar Monterey.app"
  mv "$TARGET_APP" "$BACKUP_APP"
fi

restore_previous_app() {
  rm -rf "$TARGET_APP"
  if [[ -n "$BACKUP_APP" && -d "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$TARGET_APP"
  fi
}

if ! ditto "$SOURCE_APP" "$TARGET_APP"; then
  restore_previous_app
  echo "Install failed; the previous app was restored." >&2
  exit 1
fi
if ! codesign --verify --deep --strict "$TARGET_APP"; then
  restore_previous_app
  echo "Installed bundle failed signature verification; the previous app was restored." >&2
  exit 1
fi

xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
if [[ "${CODEXBAR_INSTALL_SKIP_LAUNCH:-0}" != "1" ]]; then
  open "$TARGET_APP"
fi

echo "Installed: $TARGET_APP"
if [[ -n "$BACKUP_APP" ]]; then
  echo "Previous app backup: $BACKUP_APP"
fi
