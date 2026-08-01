#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for arch in arm64 x86_64; do
  # build_app.sh compiles the lightweight AppKit shell first and invokes
  # build_engine.sh only after that succeeds. This catches shell/Swift actor
  # errors before spending several minutes compiling the provider engine.
  "$ROOT/Scripts/build_app.sh" "$arch"
done
A="$ROOT/dist/arm64/CodexBar Monterey.app"
X="$ROOT/dist/x86_64/CodexBar Monterey.app"
OUT="$ROOT/dist/universal/CodexBar Monterey.app"
rm -rf "$OUT"
ditto "$A" "$OUT"

# Merge every architecture-specific Mach-O in the bundle, including all Sparkle
# framework/XPC/updater executables. Merging only the main app and CLI would leave an
# arm64-only updater inside an otherwise universal application.
while IFS= read -r -d '' arm_file; do
  rel="${arm_file#"$A/"}"
  intel_file="$X/$rel"
  out_file="$OUT/$rel"
  file "$arm_file" | grep -q 'Mach-O' || continue
  [[ -f "$intel_file" ]] || {
    echo "Intel build is missing Mach-O component: $rel" >&2
    exit 1
  }
  file "$intel_file" | grep -q 'Mach-O' || {
    echo "Architecture builds disagree about Mach-O component: $rel" >&2
    exit 1
  }

  arm_archs="$(lipo -archs "$arm_file")"
  intel_archs="$(lipo -archs "$intel_file")"
  if [[ "$arm_archs" == *arm64* && "$arm_archs" == *x86_64* ]]; then
    continue
  fi
  if [[ "$arm_archs" != *arm64* || "$intel_archs" != *x86_64* ]]; then
    echo "Unexpected architecture pair for $rel: [$arm_archs] + [$intel_archs]" >&2
    exit 1
  fi
  tmp="$(mktemp "${out_file}.universal.XXXXXX")"
  lipo -create "$arm_file" "$intel_file" -output "$tmp"
  chmod "$(stat -f '%Lp' "$out_file")" "$tmp"
  mv "$tmp" "$out_file"
done < <(find "$A" -type f -print0)

# Catch components that exist only in the Intel build before producing an app
# that appears complete on Apple Silicon but is incomplete on Intel Macs.
while IFS= read -r -d '' intel_file; do
  file "$intel_file" | grep -q 'Mach-O' || continue
  rel="${intel_file#"$X/"}"
  arm_file="$A/$rel"
  [[ -f "$arm_file" ]] && file "$arm_file" | grep -q 'Mach-O' || {
    echo "Apple Silicon build is missing Mach-O component: $rel" >&2
    exit 1
  }
done < <(find "$X" -type f -print0)

# Every executable image in a universal archive must contain both slices. This
# includes nested frameworks, XPC services, and Sparkle updater tools.
mach_o_count=0
while IFS= read -r -d '' output_file; do
  file "$output_file" | grep -q 'Mach-O' || continue
  mach_o_count=$((mach_o_count + 1))
  output_archs="$(lipo -archs "$output_file")"
  if [[ "$output_archs" != *arm64* || "$output_archs" != *x86_64* ]]; then
    echo "Universal bundle contains a single-architecture component: ${output_file#"$OUT/"} [$output_archs]" >&2
    exit 1
  fi
done < <(find "$OUT" -type f -print0)
[[ "$mach_o_count" -gt 0 ]] || { echo "Universal bundle contains no Mach-O files." >&2; exit 1; }

ENV_CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY-}"
set -a
# shellcheck disable=SC1090
source "${CODEXBAR_MONTEREY_ENV:-$ROOT/Config/build.env}"
set +a
if [[ -n "$ENV_CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$ENV_CODE_SIGN_IDENTITY"
fi
"$ROOT/Scripts/sign_app.sh" "$OUT"
mkdir -p "$ROOT/releases"
ditto -c -k --sequesterRsrc --keepParent "$OUT" "$ROOT/releases/CodexBar-Monterey-${APP_VERSION}.zip"
echo "$ROOT/releases/CodexBar-Monterey-${APP_VERSION}.zip"
