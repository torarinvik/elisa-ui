#!/usr/bin/env bash
# Validate the optional AppKit/Skia compositor without opening a window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"

[[ "$(uname -s)" == "Darwin" ]] || { echo "appkit skia: skipped (not macOS)"; exit 0; }
bash "$ROOT/scripts/check_skia.sh" >/dev/null
bash "$ROOT/scripts/build_appkit_skia.sh" hello >/dev/null
mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/appkit_skia_host_test.o" \
  "$ROOT/test/appkit_skia_host_test.elisa"
clang++ -std=c++20 -DSK_BUILD_FOR_MAC -fPIC -I"$ROOT" -I"$SKIA_ROOT" -c \
  "$ROOT/test/appkit_skia_host_test.cpp" -o "$ROOT/build/appkit_skia_host_test.cpp.o"
link_inputs=(
  "$ROOT/build/appkit_skia_host_test.cpp.o"
  "$ROOT/build/appkit_skia_host_test.o"
  "$ROOT/build/appkit_skia_host.o"
  "$ROOT/build/skia_canvas_shim.o"
  "$ROOT/build/skia_text_shim.o"
  "$RUNTIME"
  "$SKIA_OUT/libskia.a"
)
for extra in "$SKIA_OUT/libpng.a" "$SKIA_OUT/libzlib.a"; do
  [[ -f "$extra" ]] && link_inputs+=("$extra")
done
clang++ -Wl,-dead_strip -o "$ROOT/build/appkit_skia_host_test" "${link_inputs[@]}" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework Foundation -lz
"$ROOT/build/appkit_skia_host_test"
nm -g "$ROOT/build/hello_appkit_skia" | grep -q ' T _elisa_appkit_canvas_skia_replay$'
echo "appkit skia: optional AppKit product and off-screen compositor passed"
