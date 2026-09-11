#!/usr/bin/env bash
# Render the storefront example with real Skia, off-screen.
#
# The showcase render next door proves the renderer draws every widget. This
# one answers the other question -- what an interface BUILT with this framework
# looks like when it is composed the way a shipping application is composed --
# and it is the frame to hold next to a reference and argue about.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# A DIRECTORY OF ITS OWN. skia_canvas_shim.o and skia_text_shim.o used to be
# written to $ROOT/build by SEVEN scripts, with different flags -- check_skia.sh
# adds $SKIA_CXXFLAGS and build_appkit_skia.sh does not -- while
# check_appkit_skia.sh linked whichever copy happened to be there. run_tests.sh
# runs them in one order, check_skia.sh invokes two of them itself, and the
# result was a gate that failed in a suite and passed alone.
SKIA_SHIM_DIR="$ROOT/build/render-storefront"
mkdir -p "$SKIA_SHIM_DIR"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
SKIA_LIB="${SKIA_LIB:-$SKIA_OUT/libskia.a}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
OUTPUT="${1:-$ROOT/build/storefront-skia.png}"
WIDTH="${2:-1440}"
HEIGHT="${3:-812}"
SCALE="${4:-1.0}"

bash "$ROOT/scripts/verify_skia_pin.sh" >/dev/null
SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$SKIA_OUT" SKIA_LIB="$SKIA_LIB" bash "$ROOT/scripts/verify_skia_build.sh" >/dev/null
[[ -f "$RUNTIME" ]] || { echo "storefront skia: no runtime object at $RUNTIME" >&2; exit 2; }

mkdir -p "$ROOT/build"
# A stale object is a frame of the last good build wearing this run's name.
rm -f "$ROOT/build/storefront_skia_test.o"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/storefront_skia_test.o" \
  "$ROOT/test/storefront_skia_test.elisa"
[[ -f "$ROOT/build/storefront_skia_test.o" ]] || { echo "storefront skia: nothing compiled" >&2; exit 2; }
clang++ -std=c++20 -DSK_BUILD_FOR_MAC -fPIC -I"$ROOT" -I"$SKIA_ROOT" -c \
  "$ROOT/test/storefront_skia_host.cpp" -o "$ROOT/build/storefront_skia_host.o"
clang++ -std=c++17 -fPIC -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/skia/skia_canvas_shim.cpp" -o "$SKIA_SHIM_DIR/skia_canvas_shim.o"
clang++ -std=c++17 -fPIC -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/skia/skia_text_shim.cpp" -o "$SKIA_SHIM_DIR/skia_text_shim.o"

link_inputs=("$ROOT/build/storefront_skia_host.o" "$ROOT/build/storefront_skia_test.o"
             "$SKIA_SHIM_DIR/skia_canvas_shim.o" "$SKIA_SHIM_DIR/skia_text_shim.o" "$RUNTIME" "$SKIA_LIB")
for extra in "$SKIA_OUT/libpng.a" "$SKIA_OUT/libzlib.a"; do
  [[ -f "$extra" ]] && link_inputs+=("$extra")
done
clang++ -Wl,-dead_strip -o "$ROOT/build/storefront_skia" "${link_inputs[@]}" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework Foundation -lz

"$ROOT/build/storefront_skia" "$OUTPUT" "$WIDTH" "$HEIGHT" "$SCALE"

[[ -s "$OUTPUT" ]] || { echo "storefront skia: produced no file" >&2; exit 1; }
size="$(stat -f%z "$OUTPUT")"
# A layout that collapsed still writes a PNG -- of almost nothing. This frame
# carries four pictures and thirty-odd surfaces, so its floor is high.
if [[ "$size" -lt 120000 ]]; then
  echo "storefront skia: rendered almost nothing ($size bytes)" >&2
  exit 1
fi
echo "storefront skia: $size bytes"
