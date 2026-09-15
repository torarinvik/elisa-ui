#!/usr/bin/env bash
# Validate the optional AppKit/Skia compositor without opening a window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# A DIRECTORY OF ITS OWN. skia_canvas_shim.o and skia_text_shim.o used to be
# written to $ROOT/build by SEVEN scripts, with different flags -- check_skia.sh
# adds $SKIA_CXXFLAGS and build_appkit_skia.sh does not -- while
# check_appkit_skia.sh linked whichever copy happened to be there. run_tests.sh
# runs them in one order, check_skia.sh invokes two of them itself, and the
# result was a gate that failed in a suite and passed alone.
SKIA_SHIM_DIR="$ROOT/build/appkit-skia"
mkdir -p "$SKIA_SHIM_DIR"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
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
  "$SKIA_SHIM_DIR/appkit_skia_host.o"
  "$SKIA_SHIM_DIR/skia_canvas_shim.o"
  "$SKIA_SHIM_DIR/skia_text_shim.o"
  "$RUNTIME"
  "$SKIA_OUT/libskia.a"
)
for extra in "$SKIA_OUT/libpng.a" "$SKIA_OUT/libzlib.a"; do
  [[ -f "$extra" ]] && link_inputs+=("$extra")
done
clang++ -Wl,-dead_strip -o "$ROOT/build/appkit_skia_host_test" "${link_inputs[@]}" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework Foundation -lz
"$ROOT/build/appkit_skia_host_test"

# SAY WHAT FAILED. This was a bare `nm | grep` under `set -e`, so when it failed
# the gate exited 1 having printed nothing at all -- which is what it did inside
# one loaded suite run on 2026-09-11, right after the host test printed its own
# success line. Alone it passes with an identical pixel digest, so the cause is
# not established and this is not a fix for it; it is the difference between the
# next person seeing a symbol name and seeing nothing.
product="$ROOT/build/hello_appkit_skia"
[[ -f "$product" ]] || { echo "appkit skia: $product does not exist after the build" >&2; exit 1; }
nm_error="$ROOT/build/appkit_skia_nm.err"
if ! nm_symbols="$(nm -g "$product" 2>"$nm_error")"; then
  echo "appkit skia: nm could not inspect $product" >&2
  [[ -s "$nm_error" ]] && cat "$nm_error" >&2
  exit 1
fi
# Keep nm's complete table in memory before searching it. With `pipefail`, a
# successful `grep -q` can close a pipe while nm is still writing; nm then
# exits with SIGPIPE and turns an actually-present export into a false failure.
if ! grep -Eq '[[:space:]]T[[:space:]]+_elisa_appkit_canvas_skia_replay$' <<<"$nm_symbols"; then
  echo "appkit skia: $product does not export _elisa_appkit_canvas_skia_replay" >&2
  [[ -s "$nm_error" ]] && cat "$nm_error" >&2
  exit 1
fi
echo "appkit skia: optional AppKit product and off-screen compositor passed"
