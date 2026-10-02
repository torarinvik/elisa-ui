#!/usr/bin/env bash
# Engine plan M01: three engine viewports in one elisa-ui layout, headless.
# Needs the Elisa engine checkout (ELISA_ENGINE_ROOT, default ../elisa-engine-mocap).
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
ENGINE="$(cd -- "${ELISA_ENGINE_ROOT:-$ROOT/../elisa-engine-mocap}" && pwd)"

[[ "$(uname -s)" == "Darwin" ]] || { echo "the engine viewport is Metal, macOS only" >&2; exit 2; }
mkdir -p "$ROOT/build"
ln -sfn "$ENGINE/src" "$ROOT/build/elisa_engine_src"
clang -c -fobjc-arc -O2 -o "$ROOT/build/engine_viewport_metal.o" "$ENGINE/native/viewport_metal.m"
clang++ -c -std=c++17 -O2 -o "$ROOT/build/engine_native_fallbacks.o" "$ENGINE/native/elisa_native_fallbacks.cpp"
bash "$STAGE1/scripts/elisac_stage1.sh" -O1 -o "$ROOT/build/viewport_three_views_test.o" "$ROOT/test/viewport_three_views_test.elisa"
clang -o "$ROOT/build/viewport_three_views_test" \
  "$ROOT/build/viewport_three_views_test.o" "$ROOT/build/engine_viewport_metal.o" \
  "$ROOT/build/engine_native_fallbacks.o" "$RUNTIME" \
  -framework Foundation -framework QuartzCore -framework IOSurface -framework Metal
"$ROOT/build/viewport_three_views_test"
