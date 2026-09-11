#!/usr/bin/env bash
# Build the pinned Skia for Android, CPU raster only, from the same checkout
# the macOS renderer gates use. Nothing is fetched: the checkout must already
# be at the pinned revision (scripts/build_skia.sh puts it there). The output
# goes to its own directory so the two builds never share an object.
#
# Usage: SKIA_ROOT=~/skia scripts/build_skia_android.sh [arm64|x64]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
CPU="${1:-arm64}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa-android-$CPU}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
API="${ELISA_UI_ANDROID_API:-30}"
[[ -d "$NDK" ]] || { echo "skia android: no NDK under $SDK/ndk" >&2; exit 2; }

SKIA_ROOT="$SKIA_ROOT" bash "$ROOT/scripts/verify_skia_pin.sh" >/dev/null
NINJA="$(command -v autoninja || command -v ninja || true)"
[[ -n "$NINJA" ]] || { echo "skia android: ninja is required" >&2; exit 2; }
GN="$(command -v gn || true)"
[[ -n "$GN" ]] || GN="$SKIA_ROOT/bin/gn"
[[ -x "$GN" ]] || { echo "skia android: no usable gn" >&2; exit 2; }

# The same renderer as the macOS build -- CPU raster, PNG encode, no GPU --
# plus what Android needs to shape text: FreeType for the outlines and the
# Android font manager, which reads the system's own font configuration.
gn_args=(
  'target_os="android"'
  "target_cpu=\"$CPU\""
  "ndk=\"$NDK\""
  "ndk_api=$API"
  'is_official_build=true'
  'is_component_build=false'
  'skia_enable_tools=false'
  'skia_use_gl=false'
  'skia_use_vulkan=false'
  'skia_use_icu=false'
  'skia_use_harfbuzz=false'
  'skia_use_system_freetype2=false'
  'skia_use_system_expat=false'
  'skia_use_system_libpng=false'
  'skia_use_system_zlib=false'
  'skia_enable_fontmgr_android=true'
  'skia_use_libpng_encode=true'
  'skia_use_libpng_decode=false'
  'skia_use_libjpeg_turbo_decode=false'
  'skia_use_libjpeg_turbo_encode=false'
  'skia_use_jpeg_gainmaps=false'
  'skia_use_libwebp_encode=false'
  'skia_use_libwebp_decode=false'
  'skia_use_libavif=false'
  'skia_enable_pdf=false'
)
joined_args="${gn_args[*]}"
"$GN" gen "$SKIA_OUT" --root="$SKIA_ROOT" --args="$joined_args"
"$NINJA" -C "$SKIA_OUT" skia
[[ -f "$SKIA_OUT/libskia.a" ]] || { echo "skia android: no $SKIA_OUT/libskia.a" >&2; exit 2; }
{
  printf 'revision=%s\n' "$(git -C "$SKIA_ROOT" rev-parse HEAD)"
  printf 'lock_sha256=%s\n' "$(shasum -a 256 "$ROOT/third_party/skia.lock" | awk '{print $1}')"
  printf 'libskia_sha256=%s\n' "$(shasum -a 256 "$SKIA_OUT/libskia.a" | awk '{print $1}')"
} > "$SKIA_OUT/elisa-ui-skia-build.lock"
echo "skia android: $CPU -> $SKIA_OUT/libskia.a"
