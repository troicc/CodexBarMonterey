#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_APP="${CODEXBAR_LOCAL_TEMPLATE_APP:-/Applications/CodexBar Monterey.app}"
DISPLAY_NAME="${CODEXBAR_LOCAL_DISPLAY_NAME:-CodexBar Monterey Local Validation}"
APP_VERSION="${CODEXBAR_LOCAL_VERSION:-0.0.0}"
BUILD_NUMBER="${CODEXBAR_LOCAL_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
OUTPUT_DIR="${CODEXBAR_LOCAL_OUTPUT_DIR:-$(mktemp -d /private/tmp/codexbar-local-validation.XXXXXX)}"
OUTPUT_APP="$OUTPUT_DIR/$DISPLAY_NAME.app"

[[ -d "$TEMPLATE_APP" ]] || {
  echo "Template app not found: $TEMPLATE_APP" >&2
  echo "Install any previously validated CodexBar Monterey bundle, or set CODEXBAR_LOCAL_TEMPLATE_APP." >&2
  exit 1
}
[[ "$DISPLAY_NAME" != */* ]] || { echo "Display name must not contain '/'." >&2; exit 1; }
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  echo "CODEXBAR_LOCAL_VERSION must be a semantic version such as 0.10.0." >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "CODEXBAR_LOCAL_BUILD_NUMBER must contain digits only." >&2
  exit 1
}
[[ ! -e "$OUTPUT_APP" ]] || { echo "Output already exists: $OUTPUT_APP" >&2; exit 1; }
[[ "$OUTPUT_APP" != "$TEMPLATE_APP" ]] || { echo "Output must differ from the template app." >&2; exit 1; }

TEMPLATE_PLIST="$TEMPLATE_APP/Contents/Info.plist"
TEMPLATE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TEMPLATE_PLIST")"
[[ "$TEMPLATE_EXECUTABLE" == "CodexBarMonterey" ]] || {
  echo "Unexpected template executable: $TEMPLATE_EXECUTABLE" >&2
  exit 1
}
[[ -x "$TEMPLATE_APP/Contents/Helpers/CodexBarCLI" ]] || {
  echo "Template app has no bundled CodexBarCLI helper." >&2
  exit 1
}

BUILD_ROOT="$(mktemp -d /private/tmp/codexbar-local-build.XXXXXX)"
cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SOURCE_FILES=("$ROOT"/Sources/CodexBarMonterey/*.swift)
for arch in arm64 x86_64; do
  ARCH_ROOT="$BUILD_ROOT/$arch"
  mkdir -p "$ARCH_ROOT/module-cache"
  echo "Building local UI shell for $arch..."
  xcrun swiftc -O \
    -target "$arch-apple-macosx12.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$ARCH_ROOT/module-cache" \
    "${SOURCE_FILES[@]}" \
    -o "$ARCH_ROOT/CodexBarMonterey"
done

lipo -create \
  "$BUILD_ROOT/arm64/CodexBarMonterey" \
  "$BUILD_ROOT/x86_64/CodexBarMonterey" \
  -output "$BUILD_ROOT/CodexBarMonterey"

mkdir -p "$OUTPUT_DIR"
ditto "$TEMPLATE_APP" "$OUTPUT_APP"
install -m 755 "$BUILD_ROOT/CodexBarMonterey" "$OUTPUT_APP/Contents/MacOS/CodexBarMonterey"

OUTPUT_PLIST="$OUTPUT_APP/Contents/Info.plist"
set_plist_string() {
  local key="$1"
  local value="$2"
  if ! /usr/libexec/PlistBuddy -c "Set :$key $value" "$OUTPUT_PLIST" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$OUTPUT_PLIST"
  fi
}
set_plist_string CFBundleDisplayName "$DISPLAY_NAME"
set_plist_string CFBundleName "$DISPLAY_NAME"
set_plist_string CFBundleShortVersionString "$APP_VERSION"
set_plist_string CFBundleVersion "$BUILD_NUMBER"

codesign --force --deep --sign - "$OUTPUT_APP"

if [[ "${CODEXBAR_LOCAL_SKIP_BUNDLE_SMOKE:-0}" != "1" ]]; then
  "$ROOT/Scripts/check_macos12_compat.sh" "$OUTPUT_APP"
  CODEXBAR_SMOKE_OFFLINE=1 "$ROOT/Scripts/smoke_test_app.sh" "$OUTPUT_APP"
fi

if [[ "${CODEXBAR_LOCAL_RUN_UI_SMOKE:-0}" == "1" ]]; then
  UI_SMOKE_OUTPUT="$(mktemp /private/tmp/codexbar-local-ui-smoke.XXXXXX)"
  CODEXBAR_MONTEREY_UI_SMOKE_OUTPUT="$UI_SMOKE_OUTPUT" \
    "$OUTPUT_APP/Contents/MacOS/CodexBarMonterey"
  grep -q '^PASS' "$UI_SMOKE_OUTPUT" || {
    cat "$UI_SMOKE_OUTPUT" >&2
    exit 1
  }
  cat "$UI_SMOKE_OUTPUT"
fi

echo
echo "Local validation app: $OUTPUT_APP"
echo "Note: the UI shell is current, but CodexBarCLI and Sparkle were copied from: $TEMPLATE_APP"
echo "This bundle is ad-hoc signed and is not a release artifact."
