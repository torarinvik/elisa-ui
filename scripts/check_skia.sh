#!/usr/bin/env bash
# Validate the Skia custom painter without requiring a foregrounded window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || {
  echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2
  exit 2
}

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/ui_skia.o" "$ROOT/src/platform/skia/ui_skia.elisa"

if rg -n '#include[[:space:]]*[<"](Cocoa|AppKit)' "$ROOT/src/platform/skia/skia_canvas_shim.cpp"; then
  echo "skia: host shim must not import AppKit" >&2
  exit 1
fi

if rg -n 'safe_radius|radius[[:space:]]*>[[:space:]]*0\.0f' "$ROOT/src/platform/skia/skia_canvas_shim.cpp"; then
  echo "skia: rounded-corner policy leaked back into the C++ bridge" >&2
  exit 1
fi

if [[ -n "${SKIA_ROOT:-}" && -f "$SKIA_ROOT/include/core/SkCanvas.h" ]]; then
  cxx="${CXX:-clang++}"
  skia_cxxflags=()
  if [[ -n "${SKIA_CXXFLAGS:-}" ]]; then
    read -r -a skia_cxxflags <<< "$SKIA_CXXFLAGS"
  fi
  # Compile, but do not link, the real host bridge. Linking belongs to the
  # target's pinned Skia/Metal/GPU packaging; this check still catches stale
  # headers, C++ API drift, and accidental platform imports without opening a
  # window or requiring a surface.
  "$cxx" -std=c++17 -fPIC -I"$SKIA_ROOT" "${skia_cxxflags[@]}" \
    -c "$ROOT/src/platform/skia/skia_canvas_shim.cpp" \
    -o "$ROOT/build/skia_canvas_shim.o"
  echo "skia: Elisa painter and C++ host shim compile"
else
  echo "skia: Elisa painter compiles; C++ shim deferred until SKIA_ROOT is configured"
fi
