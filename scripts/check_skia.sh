#!/usr/bin/env bash
# Validate the Skia custom painter without requiring a foregrounded window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
require_real="${ELISA_UI_REQUIRE_REAL_SKIA:-1}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || {
  echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2
  exit 2
}
bash "$ROOT/scripts/check_toolchain.sh"

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/ui_skia.o" "$ROOT/src/platform/skia/ui_skia.elisa"

if ! nm -g "$ROOT/build/ui_skia.o" | grep -Eq 'elisa_skia_abi_version$'; then
  echo "skia: ABI version symbol is not exported by the Elisa object" >&2
  exit 1
fi
if ! nm -g "$ROOT/build/ui_skia.o" | grep -Eq 'elisa_skia_render_frame_with_font_status$'; then
  echo "skia: scoped-font render symbol is not exported by the Elisa object" >&2
  exit 1
fi
if ! nm -g "$ROOT/build/ui_skia.o" | grep -Eq 'elisa_skia_render_frame$'; then
  echo "skia: one-shot render symbol is not exported by the Elisa object" >&2
  exit 1
fi
if ! nm -g "$ROOT/build/ui_skia.o" | grep -Eq 'elisa_skia_render_frame_scaled$'; then
  echo "skia: scaled one-shot render symbol is not exported by the Elisa object" >&2
  exit 1
fi

if rg -n '#include[[:space:]]*[<"](Cocoa|AppKit)' "$ROOT/src/platform/skia/skia_canvas_shim.cpp"; then
  echo "skia: host shim must not import AppKit" >&2
  exit 1
fi

if rg -n 'safe_radius|radius[[:space:]]*>[[:space:]]*0\.0f' "$ROOT/src/platform/skia/skia_canvas_shim.cpp"; then
  echo "skia: rounded-corner policy leaked back into the C++ bridge" >&2
  exit 1
fi

if [[ -n "${SKIA_ROOT:-}" ]]; then
  bash "$ROOT/scripts/verify_skia_pin.sh"
  cxx="${CXX:-clang++}"
  skia_cxxflags=()
  if [[ -n "${SKIA_CXXFLAGS:-}" ]]; then
    read -r -a skia_cxxflags <<< "$SKIA_CXXFLAGS"
  fi
  # Compile the real host bridge. If the pinned CPU-raster archive is present,
  # the nested fixture also links and runs it against an off-screen surface;
  # otherwise this still catches stale headers, C++ API drift, and accidental
  # platform imports without opening a window or requiring a surface.
  if (( ${#skia_cxxflags[@]} > 0 )); then
    "$cxx" -std=c++17 -fPIC -I"$SKIA_ROOT" "${skia_cxxflags[@]}" \
      -c "$ROOT/src/platform/skia/skia_canvas_shim.cpp" \
      -o "$ROOT/build/skia_canvas_shim.o"
  else
    "$cxx" -std=c++17 -fPIC -I"$SKIA_ROOT" \
      -c "$ROOT/src/platform/skia/skia_canvas_shim.cpp" \
      -o "$ROOT/build/skia_canvas_shim.o"
  fi
  echo "skia: Elisa painter and C++ host shim compile"
  skia_out="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
  if [[ -f "$skia_out/libskia.a" ]]; then
    SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$skia_out" bash "$ROOT/scripts/check_skia_offscreen.sh"
    SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$skia_out" bash "$ROOT/scripts/check_showcase_skia.sh"
  elif [[ "$require_real" == "1" ]]; then
    echo "skia: required CPU-raster archive is missing at $skia_out/libskia.a" >&2
    echo "skia: build the pinned checkout from third_party/skia.lock or set ELISA_UI_REQUIRE_REAL_SKIA=0 for a compiler-only edit loop" >&2
    exit 2
  else
    echo "skia: pinned headers compile; off-screen fixture deferred until $skia_out/libskia.a exists"
  fi
elif [[ "$require_real" == "1" ]]; then
  echo "skia: real renderer checks are required; set SKIA_ROOT to the checkout pinned in third_party/skia.lock" >&2
  echo "skia: set ELISA_UI_REQUIRE_REAL_SKIA=0 only for a compiler-only edit loop" >&2
  exit 2
else
  echo "skia: Elisa painter compiles; C++ shim deferred until SKIA_ROOT is configured"
fi
