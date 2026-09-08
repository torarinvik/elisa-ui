#!/usr/bin/env bash
# Build and run the real CPU-raster Skia acceptance fixture headlessly.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
SKIA_LIB="${SKIA_LIB:-$SKIA_OUT/libskia.a}"

bash "$ROOT/scripts/check_toolchain.sh"
bash "$ROOT/scripts/verify_skia_pin.sh"
SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$SKIA_OUT" SKIA_LIB="$SKIA_LIB" bash "$ROOT/scripts/verify_skia_build.sh"
[[ -f "$SKIA_LIB" ]] || { echo "skia offscreen: no Skia library at $SKIA_LIB" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "skia offscreen: no runtime object at $RUNTIME" >&2; exit 2; }

mkdir -p "$ROOT/build"
ELISA_OBJECT="$ROOT/build/skia_offscreen_test.o"
HOST_OBJECT="$ROOT/build/skia_offscreen_host.o"
HOST_BINARY="$ROOT/build/skia_offscreen_test"
SHIM_OBJECT="$ROOT/build/skia_canvas_shim.o"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ELISA_OBJECT" "$ROOT/test/skia_offscreen_test.elisa"
clang++ -std=c++20 -DSK_BUILD_FOR_MAC -fPIC -I"$ROOT" -I"$SKIA_ROOT" -c \
  "$ROOT/test/skia_offscreen_host.cpp" -o "$HOST_OBJECT"
clang++ -std=c++17 -fPIC -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/skia/skia_canvas_shim.cpp" -o "$SHIM_OBJECT"

link_inputs=("$HOST_OBJECT" "$ELISA_OBJECT" "$SHIM_OBJECT" "$RUNTIME" "$SKIA_LIB")
for extra in "$SKIA_OUT/libpng.a" "$SKIA_OUT/libzlib.a"; do
  [[ -f "$extra" ]] && link_inputs+=("$extra")
done
clang++ -Wl,-dead_strip -o "$HOST_BINARY" "${link_inputs[@]}" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework Foundation -lz

snapshot="${ELISA_UI_SKIA_SNAPSHOT:-}"
render_iterations="${ELISA_UI_SKIA_RENDER_ITERATIONS:-16}"
if [[ ! "$render_iterations" =~ ^[1-9][0-9]*$ ]] || (( render_iterations > 10000 )); then
  echo "skia offscreen: ELISA_UI_SKIA_RENDER_ITERATIONS must be an integer in 1..10000 (got $render_iterations)" >&2
  exit 2
fi
run_dir="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-skia.XXXXXX")"
cleanup() { rm -rf "$run_dir"; }
trap cleanup EXIT

first_snapshot="$snapshot"
if [[ -z "$first_snapshot" ]]; then
  first_snapshot="$run_dir/frame-first.png"
fi
second_snapshot="$run_dir/frame-second.png"
first_output="$(ELISA_UI_SKIA_RENDER_ITERATIONS="$render_iterations" "$HOST_BINARY" "$first_snapshot")"
printf '%s\n' "$first_output"
second_output="$(ELISA_UI_SKIA_RENDER_ITERATIONS="$render_iterations" "$HOST_BINARY" "$second_snapshot")"
second_digest="$(sed -n 's/.*pixel_digest=\([[:xdigit:]]*\).*/\1/p' <<<"$second_output" | tail -n 1)"
first_digest="$(sed -n 's/.*pixel_digest=\([[:xdigit:]]*\).*/\1/p' <<<"$first_output" | tail -n 1)"
[[ -n "$first_digest" && "$first_digest" == "$second_digest" ]] || {
  echo "skia offscreen: fresh-process pixel digest mismatch (first=$first_digest second=$second_digest)" >&2
  exit 12
}
echo "skia offscreen: fresh-process replay digest verified pixel_digest=$second_digest"
