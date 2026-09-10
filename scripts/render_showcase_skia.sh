#!/usr/bin/env bash
# Render every page of the shipped showcase with real Skia, off-screen.
#
# The hello fixture next door asserts pixels. This one produces the pictures:
# five pages of the showcase -- its theme, its controls, its scrolling list and
# its custom-painted canvas -- rasterized by the same painter a window uses. It
# is how the renderer's output is looked at rather than only measured, and it
# doubles as coverage: a page that stops laying out produces a nearly empty
# frame, which is what the size check below catches.
#
# Usage: render_showcase_skia.sh [output-prefix] [width] [height]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
SKIA_LIB="${SKIA_LIB:-$SKIA_OUT/libskia.a}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
PREFIX="${1:-$ROOT/build/showcase-skia}"
WIDTH="${2:-1180}"
HEIGHT="${3:-800}"

bash "$ROOT/scripts/verify_skia_pin.sh" >/dev/null
SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$SKIA_OUT" SKIA_LIB="$SKIA_LIB" bash "$ROOT/scripts/verify_skia_build.sh" >/dev/null
[[ -f "$RUNTIME" ]] || { echo "showcase skia: no runtime object at $RUNTIME" >&2; exit 2; }

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/showcase_app_skia_test.o" \
  "$ROOT/test/showcase_app_skia_test.elisa"
clang++ -std=c++20 -DSK_BUILD_FOR_MAC -fPIC -I"$ROOT" -I"$SKIA_ROOT" -c \
  "$ROOT/test/showcase_app_skia_host.cpp" -o "$ROOT/build/showcase_app_skia_host.o"
clang++ -std=c++17 -fPIC -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/skia/skia_canvas_shim.cpp" -o "$ROOT/build/skia_canvas_shim.o"
clang++ -std=c++17 -fPIC -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/skia/skia_text_shim.cpp" -o "$ROOT/build/skia_text_shim.o"

link_inputs=("$ROOT/build/showcase_app_skia_host.o" "$ROOT/build/showcase_app_skia_test.o"
             "$ROOT/build/skia_canvas_shim.o" "$ROOT/build/skia_text_shim.o" "$RUNTIME" "$SKIA_LIB")
for extra in "$SKIA_OUT/libpng.a" "$SKIA_OUT/libzlib.a"; do
  [[ -f "$extra" ]] && link_inputs+=("$extra")
done
clang++ -Wl,-dead_strip -o "$ROOT/build/showcase_app_skia" "${link_inputs[@]}" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework Foundation -lz

"$ROOT/build/showcase_app_skia" "$PREFIX" "$WIDTH" "$HEIGHT" >/dev/null

# A page that failed to lay out still writes a PNG -- of almost nothing. A
# flat frame compresses to a fraction of a populated one, so a floor here is
# what separates "rendered" from "wrote a file".
for page in 1 2 3 4 5; do
  file="$PREFIX-page$page.png"
  [[ -s "$file" ]] || { echo "showcase skia: page $page produced no file" >&2; exit 1; }
  size="$(stat -f%z "$file")"
  if [[ "$size" -lt 20000 ]]; then
    echo "showcase skia: page $page rendered almost nothing ($size bytes)" >&2
    exit 1
  fi
  echo "showcase skia: page $page rendered ${WIDTH}x${HEIGHT} ($size bytes) -> $file"
done
# ...and one frame with the keyboard focus on a control. Every page above is
# rendered with nothing focused, so without this the focus ring -- the thing a
# keyboard user navigates by -- appears in no picture and is checked by nothing.
focus_file="$PREFIX-focus.png"
[[ -s "$focus_file" ]] || { echo "showcase skia: the focused frame produced no file" >&2; exit 1; }
focus_size="$(stat -f%z "$focus_file")"
if [[ "$focus_size" -lt 20000 ]]; then
  echo "showcase skia: the focused frame rendered almost nothing ($focus_size bytes)" >&2
  exit 1
fi
# The ring has to CHANGE the frame. A focused render identical to the unfocused
# one means the ring stopped being drawn, which no size check would notice.
if cmp -s "$PREFIX-page2.png" "$focus_file"; then
  echo "showcase skia: the focused frame is identical to the unfocused one; no focus ring was drawn" >&2
  exit 1
fi
echo "showcase skia: focus ring rendered ${WIDTH}x${HEIGHT} ($focus_size bytes) -> $focus_file"
# ...and the light palette, which exercises the other half of the depth policy.
light_file="$PREFIX-light.png"
[[ -s "$light_file" ]] || { echo "showcase skia: the light frame produced no file" >&2; exit 1; }
light_size="$(stat -f%z "$light_file")"
if [[ "$light_size" -lt 20000 ]]; then
  echo "showcase skia: the light frame rendered almost nothing ($light_size bytes)" >&2
  exit 1
fi
if cmp -s "$PREFIX-page1.png" "$light_file"; then
  echo "showcase skia: the light frame is identical to the dark one; the palette did not switch" >&2
  exit 1
fi
echo "showcase skia: light palette rendered ${WIDTH}x${HEIGHT} ($light_size bytes) -> $light_file"
# ...and the modal, which is a rendering case of its own: a raised sheet with an
# accent ring, over a shell disabled beneath it.
dialog_file="$PREFIX-dialog.png"
[[ -s "$dialog_file" ]] || { echo "showcase skia: the dialog frame produced no file" >&2; exit 1; }
dialog_size="$(stat -f%z "$dialog_file")"
if [[ "$dialog_size" -lt 20000 ]]; then
  echo "showcase skia: the dialog frame rendered almost nothing ($dialog_size bytes)" >&2
  exit 1
fi
if cmp -s "$PREFIX-page4.png" "$dialog_file"; then
  echo "showcase skia: the dialog frame is identical to the page beneath it; the dialog did not open" >&2
  exit 1
fi
echo "showcase skia: dialog rendered ${WIDTH}x${HEIGHT} ($dialog_size bytes) -> $dialog_file"
# ...and once at a retina backing scale. A frame that only looks right at 1.0 is
# a frame tuned to one grid rather than derived from the geometry.
retina_file="$PREFIX-retina.png"
[[ -s "$retina_file" ]] || { echo "showcase skia: the retina frame produced no file" >&2; exit 1; }
retina_size="$(stat -f%z "$retina_file")"
# Four times the pixels of the 1x frame, so the floor is proportionally higher.
if [[ "$retina_size" -lt 60000 ]]; then
  echo "showcase skia: the retina frame rendered almost nothing ($retina_size bytes)" >&2
  exit 1
fi
echo "showcase skia: retina frame rendered $((WIDTH * 2))x$((HEIGHT * 2)) at 2x ($retina_size bytes) -> $retina_file"
# ...and a control under the cursor, and the same control held down. Hover and
# press are appearances, and every other frame here is of controls at rest.
for state in hover pressed; do
  state_file="$PREFIX-$state.png"
  [[ -s "$state_file" ]] || { echo "showcase skia: the $state frame produced no file" >&2; exit 1; }
  state_size="$(stat -f%z "$state_file")"
  if [[ "$state_size" -lt 20000 ]]; then
    echo "showcase skia: the $state frame rendered almost nothing ($state_size bytes)" >&2
    exit 1
  fi
  echo "showcase skia: $state state rendered ${WIDTH}x${HEIGHT} ($state_size bytes) -> $state_file"
done
# Three DIFFERENT pictures. A pointer that reached nothing still writes two
# perfectly good frames of a control at rest, which is how this check earns its
# keep: it caught exactly that, with the modal left open and the shell disabled
# beneath it, before the frames were looked at.
if cmp -s "$PREFIX-page1.png" "$PREFIX-hover.png"; then
  echo "showcase skia: the hover frame is identical to the resting one; the pointer reached no control" >&2
  exit 1
fi
if cmp -s "$PREFIX-hover.png" "$PREFIX-pressed.png"; then
  echo "showcase skia: the pressed frame is identical to the hovered one; the press changed nothing" >&2
  exit 1
fi
echo "showcase skia: all five showcase pages rendered by the real renderer"
