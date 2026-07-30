#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.4}"
TOOLS_ROOT="${SPARKLE_TOOLS_DIR:-$ROOT/.tools/Sparkle-$SPARKLE_VERSION}"
PRIVATE_KEY_FILE="${1:-$HOME/.config/codexbar-monterey/sparkle-private-key}"

download_tools() {
  mkdir -p "$ROOT/.tools"
  local archive="$ROOT/.tools/Sparkle-$SPARKLE_VERSION.tar.xz"
  local url="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  if command -v gh >/dev/null 2>&1; then
    gh release download "$SPARKLE_VERSION" \
      --repo sparkle-project/Sparkle \
      --pattern "Sparkle-$SPARKLE_VERSION.tar.xz" \
      --dir "$ROOT/.tools" \
      --clobber
  else
    echo "GitHub CLI not found; downloading Sparkle tools with the system curl."
    curl --fail --location --retry 3 --output "$archive" "$url"
  fi
  rm -rf "$TOOLS_ROOT"
  mkdir -p "$TOOLS_ROOT"
  tar -xJf "$archive" -C "$TOOLS_ROOT" --strip-components=1
}

GENERATE_KEYS="$TOOLS_ROOT/bin/generate_keys"
[[ -x "$GENERATE_KEYS" ]] || download_tools
[[ -x "$GENERATE_KEYS" ]] || { echo "Sparkle generate_keys was not found." >&2; exit 1; }

mkdir -p "$(dirname "$PRIVATE_KEY_FILE")"
if [[ -e "$PRIVATE_KEY_FILE" ]]; then
  echo "Refusing to overwrite existing private key: $PRIVATE_KEY_FILE" >&2
  exit 1
fi

# First invocation creates the EdDSA key in the login Keychain and prints the
# SUPublicEDKey value. The second exports the private key for CI storage.
"$GENERATE_KEYS"
"$GENERATE_KEYS" -x "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"

cat <<MSG

Private key exported to:
  $PRIVATE_KEY_FILE

Store the complete file content as the GitHub Actions secret SPARKLE_PRIVATE_KEY.
Copy the SUPublicEDKey printed above into the GitHub secret SPARKLE_PUBLIC_KEY.
Never commit the private key or paste it into an issue/log.
MSG
