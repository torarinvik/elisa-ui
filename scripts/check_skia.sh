#!/usr/bin/env bash
# Validate the Skia custom painter without requiring a foregrounded window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
require_real="${ELISA_UI_REQUIRE_REAL_SKIA:-1}"
case "$require_real" in
  0|1) ;;
  *)
    echo "skia: ELISA_UI_REQUIRE_REAL_SKIA must be 0 or 1 (got $require_real)" >&2
    exit 2
    ;;
esac

[[ -x "$STAGE1/bin/elisac-stage1" ]] || {
  echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2
  exit 2
}
bash "$ROOT/scripts/check_toolchain.sh"

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/ui_skia.o" "$ROOT/src/platform/skia/ui_skia.elisa"

# `nm | grep -q` is a trap under pipefail: grep can close the pipe on a match
# before nm has finished writing its table, and the pipeline then reports nm's
# SIGPIPE rather than grep's success. Read the table once and search that.
skia_symbols="$(nm -g "$ROOT/build/ui_skia.o")"
for skia_symbol in \
  elisa_skia_abi_version \
  elisa_skia_render_frame_with_font_status \
  elisa_skia_render_frame \
  elisa_skia_render_frame_scaled; do
  case "$skia_symbols" in
    *"$skia_symbol"*) ;;
    *)
      echo "skia: $skia_symbol is not exported by the Elisa object" >&2
      exit 1
      ;;
  esac
done

# Compiling the painter alone does not exercise the compositor seam, which is
# how the AppKit+Skia product silently stopped compiling: the frame-font scope
# it needs had been made private to UiSkia and nothing linked the two. These
# entries need no Skia headers, so they are checked even without SKIA_ROOT.
if [[ "$(uname -s)" == "Darwin" ]]; then
  for skia_entry in hello showcase; do
    entry="$ROOT/examples/$skia_entry/appkit_skia_canvas_main.elisa"
    [[ -f "$entry" ]] || continue
    bash "$STAGE1/scripts/elisac_stage1.sh" -O0 \
      -o "$ROOT/build/${skia_entry}_appkit_skia_entry.o" "$entry"
  done
  echo "skia: the AppKit compositor entries compile"
fi

if rg -n '#include[[:space:]]*[<"](Cocoa|AppKit)' "$ROOT/src/platform/skia/skia_canvas_shim.cpp" "$ROOT/src/platform/skia/skia_text_shim.cpp" "$ROOT/src/platform/skia/skia_shim_common.h"; then
  echo "skia: host shim must not import AppKit" >&2
  exit 1
fi

if rg -n 'safe_radius|radius[[:space:]]*>[[:space:]]*0\.0f' "$ROOT/src/platform/skia/skia_canvas_shim.cpp" "$ROOT/src/platform/skia/skia_text_shim.cpp" "$ROOT/src/platform/skia/skia_shim_common.h"; then
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
    "$cxx" -std=c++17 -fPIC -I"$SKIA_ROOT" "${skia_cxxflags[@]}" \
      -c "$ROOT/src/platform/skia/skia_text_shim.cpp" \
      -o "$ROOT/build/skia_text_shim.o"
  else
    "$cxx" -std=c++17 -fPIC -I"$SKIA_ROOT" \
      -c "$ROOT/src/platform/skia/skia_canvas_shim.cpp" \
      -o "$ROOT/build/skia_canvas_shim.o"
    "$cxx" -std=c++17 -fPIC -I"$SKIA_ROOT" \
      -c "$ROOT/src/platform/skia/skia_text_shim.cpp" \
      -o "$ROOT/build/skia_text_shim.o"
  fi
  echo "skia: Elisa painter and C++ host shim compile"
  skia_out="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
  if [[ -f "$skia_out/libskia.a" ]]; then
    SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$skia_out" SKIA_LIB="$skia_out/libskia.a" bash "$ROOT/scripts/verify_skia_build.sh"
    SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$skia_out" bash "$ROOT/scripts/check_skia_offscreen.sh"
    SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$skia_out" bash "$ROOT/scripts/check_showcase_skia.sh"
    # Every page of the shipped showcase, through the real painter. The hello
    # fixture above asserts pixels on one frame; this covers the theme, the
    # controls, the scrolling list and the custom canvas, and leaves the
    # pictures behind in build/.
    SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$skia_out" bash "$ROOT/scripts/render_showcase_skia.sh"
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
