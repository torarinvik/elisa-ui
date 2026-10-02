#!/usr/bin/env bash
# Keep AppKit's resource-binding lifecycle test runnable before the full canvas
# matrix, which may stop on an unrelated backend codegen decline.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "AppKit image upload: skipped (not macOS)"
  exit 0
fi

STAGE1="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no Stage1 compiler at $STAGE1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no Stage1 runtime at $RUNTIME" >&2; exit 2; }
ELISA_UI_STAGE1="$STAGE1" bash "$ROOT/scripts/check_toolchain.sh" --report >&2

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-appkit-image.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

"$STAGE1/bin/elisac-stage1" -emit obj -O0 \
  -o "$WORK/appkit_canvas_image_upload_test.o" \
  "$ROOT/test/appkit_canvas_image_upload_test.elisa"
SDL_LIB="${ELISA_UI_SDL_LIB:-/opt/homebrew/lib}"
clang -Wl,-dead_strip -o "$WORK/appkit_canvas_image_upload_test" \
  "$WORK/appkit_canvas_image_upload_test.o" "$RUNTIME" \
  -L"$SDL_LIB" -lSDL3 -lSDL3_ttf -Wl,-rpath,"$SDL_LIB" \
  -framework CoreFoundation -framework AppKit
"$WORK/appkit_canvas_image_upload_test"
echo "AppKit image upload: binding-lifecycle gate passed"
