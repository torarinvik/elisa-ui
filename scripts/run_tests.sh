#!/usr/bin/env bash
# Build and run the elisa-ui test programs. These need no window or backend:
# each links against the core plus the layer under test and reports through its
# exit status.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
SDL_LIB="${ELISA_UI_SDL_LIB:-/opt/homebrew/lib}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME" >&2; exit 2; }

mkdir -p "$ROOT/build"
status=0

SKIA_TEST_SHIM="$ROOT/build/skia_painter_shim.o"
clang -c -Wall -Wextra -Werror -o "$SKIA_TEST_SHIM" "$ROOT/test/skia_painter_shim.c"

if ! bash "$ROOT/scripts/check_source_sizes.sh"; then
  echo "FAIL source sizes"
  status=1
fi

if ! bash "$ROOT/scripts/check_global_names.sh"; then
  echo "FAIL global names"
  status=1
fi

# The C boundary is checked by building a real C program against the library --
# the header and the Elisa side are two hand-written descriptions of one ABI, and
# nothing in the Elisa suite sees the header.
if ! bash "$ROOT/scripts/check_capi.sh"; then
  echo "FAIL capi"
  status=1
fi

# The AppKit backend builds REAL NSViews, so it needs Cocoa and its own link
# line. Skips itself off macOS. It never shows a window.
if ! bash "$ROOT/scripts/check_appkit.sh"; then
  echo "FAIL appkit"
  status=1
fi

# The custom AppKit renderer is a separate architecture from native controls:
# validate its Elisa/Objective-C callback boundary and packaged .app as well.
if ! bash "$ROOT/scripts/check_appkit_canvas.sh"; then
  echo "FAIL appkit canvas"
  status=1
fi

for source in "$ROOT"/test/*_test.elisa; do
  name="$(basename "$source" .elisa)"
  bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/$name.o" "$source"
  # Link SDL for tests that exercise the native backend; the others simply
  # do not reference these symbols.
  link_inputs=("$RUNTIME")
  if [[ "$name" == "skia_painter_test" ]]; then
    link_inputs=("$SKIA_TEST_SHIM" "$RUNTIME")
  fi
  if [[ "$name" == "appkit_canvas_keymap_test" && "$(uname -s)" == "Darwin" ]]; then
    clang -Wl,-dead_strip -o "$ROOT/build/$name" "$ROOT/build/$name.o" "${link_inputs[@]}" -L"$SDL_LIB" -lSDL3 -lSDL3_ttf -Wl,-rpath,"$SDL_LIB" -framework CoreFoundation
  else
    clang -Wl,-dead_strip -o "$ROOT/build/$name" "$ROOT/build/$name.o" "${link_inputs[@]}" -L"$SDL_LIB" -lSDL3 -lSDL3_ttf -Wl,-rpath,"$SDL_LIB"
  fi
  if "$ROOT/build/$name"; then
    echo "PASS $name"
  else
    echo "FAIL $name" >&2
    status=1
  fi
done

exit "$status"
