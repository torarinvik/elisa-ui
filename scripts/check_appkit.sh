#!/usr/bin/env bash
# Build and run the AppKit backend check. macOS only: it creates real NSViews.
# Never shows a window, so it runs headless.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../elisa-ui-worktrees/stage1}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "appkit: skipped (not macOS)"
  exit 0
fi

mkdir -p "$ROOT/build"
if grep -Eq 'elisa_appkit_(create|set_(text|frame))\b' "$ROOT/src/platform/appkit/appkit_shim.m" "$ROOT/src/platform/appkit/ui_appkit.elisa"; then
  echo "appkit: generic control dispatch leaked back into the native boundary" >&2
  exit 1
fi
clang -c -fobjc-arc -o "$ROOT/build/appkit_shim.o" "$ROOT/src/platform/appkit/appkit_shim.m"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/appkit_check.o" "$ROOT/src/platform/appkit/appkit_check.elisa"
clang -Wl,-dead_strip -o "$ROOT/build/appkit_check" \
  "$ROOT/build/appkit_check.o" "$ROOT/build/appkit_shim.o" "$RUNTIME" -framework Cocoa
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_window_title$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_button_title$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_field_text$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_window_frame$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_view_frame$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_window_style_titled$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_window_style_closable$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_window_style_miniaturizable$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_window_style_resizable$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_window_style_utility$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_window_with_style$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_floating_panel$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_vertical_scroll_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_horizontal_scroll_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_scroll_document_frame$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_attach_to_window$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_attach_to_scroll_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_attach_to_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_button_state$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_slider_state$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_progress_value$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_scroll_has_vertical$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_scroll_has_horizontal$'
if nm -g "$ROOT/build/appkit_check" | grep -Eq ' T _elisa_appkit_(create|set_(text|frame))$'; then
  echo "appkit: obsolete generic entry point survived the link" >&2
  exit 1
fi
if nm -g "$ROOT/build/appkit_check" | grep -Eq ' T _elisa_appkit_create_(fixed_window|resizable_window|window|scroll_view)$'; then
  echo "appkit: undifferentiated window or scroll creation survived the link" >&2
  exit 1
fi
"$ROOT/build/appkit_check"
