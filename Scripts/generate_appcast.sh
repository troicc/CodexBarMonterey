#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVES_DIR="${1:-$ROOT/releases}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
OUTPUT_PATH="${OUTPUT_PATH:-$ROOT/appcast.xml}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.4}"
TOOLS_ROOT="${SPARKLE_TOOLS_DIR:-$ROOT/.tools/Sparkle-$SPARKLE_VERSION}"

[[ -d "$ARCHIVES_DIR" ]] || { echo "Archives directory not found: $ARCHIVES_DIR" >&2; exit 1; }
[[ -n "$DOWNLOAD_URL_PREFIX" ]] || { echo "Set DOWNLOAD_URL_PREFIX to the HTTPS release-asset directory." >&2; exit 1; }

find_generate_appcast() {
  local candidate
  for candidate in \
    "$TOOLS_ROOT/bin/generate_appcast" \
    "$TOOLS_ROOT/generate_appcast"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  find "$ROOT/.build" "$ROOT/.tools" -type f -name generate_appcast -perm -111 2>/dev/null | head -1
}

GENERATE_APPCAST="$(find_generate_appcast || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  mkdir -p "$ROOT/.tools"
  ARCHIVE="$ROOT/.tools/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "Downloading Sparkle $SPARKLE_VERSION tools..."
  SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  if command -v gh >/dev/null 2>&1; then
    gh release download "$SPARKLE_VERSION" \
      --repo sparkle-project/Sparkle \
      --pattern "Sparkle-$SPARKLE_VERSION.tar.xz" \
      --dir "$ROOT/.tools" \
      --clobber
  else
    curl --fail --location --retry 3 --output "$ARCHIVE" "$SPARKLE_URL"
  fi
  rm -rf "$TOOLS_ROOT"
  mkdir -p "$TOOLS_ROOT"
  tar -xJf "$ARCHIVE" -C "$TOOLS_ROOT" --strip-components=1
  GENERATE_APPCAST="$(find_generate_appcast || true)"
fi

[[ -x "$GENERATE_APPCAST" ]] || { echo "Sparkle generate_appcast tool not found." >&2; exit 1; }

# Sparkle recommends keeping the EdDSA private key out of command-line arguments.
# In CI, pass it over stdin with --ed-key-file -.
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  [[ -f "$SPARKLE_PRIVATE_KEY_FILE" ]] || { echo "Private-key file not found." >&2; exit 1; }
  "$GENERATE_APPCAST" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --output-path "$OUTPUT_PATH" \
    "$ARCHIVES_DIR"
elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --output-path "$OUTPUT_PATH" \
    "$ARCHIVES_DIR"
else
  echo "Set SPARKLE_PRIVATE_KEY (CI secret) or SPARKLE_PRIVATE_KEY_FILE." >&2
  exit 1
fi

[[ -s "$OUTPUT_PATH" ]] || { echo "Appcast was not generated: $OUTPUT_PATH" >&2; exit 1; }
grep -q 'sparkle:edSignature=' "$OUTPUT_PATH" || {
  echo "Generated appcast has no EdDSA archive signature; aborting publish." >&2
  exit 1
}
grep -q '<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>' "$OUTPUT_PATH" || {
  echo "Warning: appcast does not explicitly show minimumSystemVersion 12.0." >&2
}
echo "$OUTPUT_PATH"
