#!/usr/bin/env bash
# The GTK backend: build it, link it against real GTK, and run it.
#
# THE LINUX HALF OF THE NATIVE STORY. The seam's mapping table carried a GTK
# column for years while no such backend existed, and Windows and Linux had the
# Skia canvas through SDL3 and nothing else. This gate is what keeps the column
# honest from here on.
#
# Run on macOS, where GTK is a supported target. That is not the same as having
# run on Linux -- and check_gtk_linux.sh now does exactly that, with this same
# fixture, inside an OrbStack machine against a real X server. This gate is
# still worth keeping: a binding that compiles and passes in two places is
# better evidence than one that does so in one. What it proves is
# that the backend compiles against the real headers, links against the real
# library, and that live GtkWindows, GtkButtons and GtkEntries come out with the
# types, the state, the tree shape and the colours the framework asked for. A
# GTK widget does not know which platform it is on; the windowing below it does.
#
# The colour half briefly presents a window, because GTK does not draw a widget
# that was never shown and a colour nobody painted is not a colour.
#
# It skips itself when GTK is not installed, and the fixture skips itself again
# when there is no display -- gtk_init_check answers rather than aborting, which
# is the same courtesy the iOS device gates get.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
OUT="$ROOT/build/gtk"

if ! command -v pkg-config >/dev/null || ! pkg-config --exists gtk4; then
  echo "gtk: skipped (no gtk4; brew install gtk4, or apt install libgtk-4-dev)"
  exit 0
fi

mkdir -p "$OUT"
clang -c -Wall -Wextra -Werror $(pkg-config --cflags gtk4) \
  -o "$OUT/gtk_shim.o" "$ROOT/src/platform/gtk/gtk_shim.c"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$OUT/gtk_check.o" \
  "$ROOT/src/platform/gtk/gtk_check.elisa"
clang -Wl,-dead_strip -o "$OUT/gtk_check" \
  "$OUT/gtk_check.o" "$OUT/gtk_shim.o" "$RUNTIME" $(pkg-config --libs gtk4)

# EVERY EXPORT THE SHIM CALLS MUST EXIST, in both directions -- the same
# two-way check the UIKit gate makes, which is what caught a backend entry with
# no host stand-in earlier today.
for symbol in elisa_gtk_action elisa_gtk_text_action; do
  nm "$OUT/gtk_check.o" | grep -q "T _$symbol" || {
    echo "gtk: $symbol is called by the shim and exported by nothing" >&2
    exit 1
  }
done

"$OUT/gtk_check"
echo "gtk: real GtkWindows, GtkButtons and GtkEntries built, typed, shaped and coloured as asked"
