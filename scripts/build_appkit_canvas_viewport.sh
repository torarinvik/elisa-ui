#!/usr/bin/env bash
# Build examples/viewport: an Elisa engine viewport (Metal, IOSurface ring)
# hosted in an elisa-ui AppKit canvas panel. The engine is an external checkout:
# ELISA_ENGINE_ROOT (default ../elisa-engine-mocap) supplies src/viewport and
# native/viewport_metal.m. Smoke-test without showing a window:
#   ELISA_UI_SMOKE_FRAMES=1 build/viewport_appkit_canvas
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
ENGINE="$(cd -- "${ELISA_ENGINE_ROOT:-$ROOT/../elisa-engine-mocap}" && pwd)"
OPT_LEVEL="${ELISA_UI_OPT_LEVEL:-2}"

[[ "$(uname -s)" == "Darwin" ]] || { echo "the AppKit canvas backend is macOS only" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME (set ELISA_UI_STAGE1)" >&2; exit 2; }
[[ -f "$ENGINE/src/viewport/viewport.elisa" && -f "$ENGINE/native/viewport_metal.m" ]] || { echo "no engine viewport under $ENGINE (set ELISA_ENGINE_ROOT)" >&2; exit 2; }
mkdir -p "$ROOT/build"
ln -sfn "$ENGINE/src" "$ROOT/build/elisa_engine_src"
clang -c -fobjc-arc -Wall -Wextra -Wconversion -Wsign-conversion -Werror \
  -o "$ROOT/build/appkit_canvas_shim.o" "$ROOT/src/platform/appkit/appkit_canvas_shim.m"
clang -c -fobjc-arc -O2 -o "$ROOT/build/engine_viewport_metal.o" "$ENGINE/native/viewport_metal.m"
# The engine's weak fallbacks for runtime hooks a plain host does not define.
clang++ -c -std=c++17 -O2 -o "$ROOT/build/engine_native_fallbacks.o" "$ENGINE/native/elisa_native_fallbacks.cpp"
bash "$STAGE1/scripts/elisac_stage1.sh" "-O$OPT_LEVEL" -o "$ROOT/build/viewport_appkit_canvas.o" "$ROOT/examples/viewport/appkit_canvas_main.elisa"
clang -o "$ROOT/build/viewport_appkit_canvas" \
  "$ROOT/build/viewport_appkit_canvas.o" "$ROOT/build/appkit_canvas_shim.o" "$ROOT/build/engine_viewport_metal.o" \
  "$ROOT/build/engine_native_fallbacks.o" "$RUNTIME" \
  -framework Cocoa -framework CoreText -framework CoreGraphics -framework ImageIO \
  -framework QuartzCore -framework IOSurface -framework Metal
echo "built $ROOT/build/viewport_appkit_canvas"
