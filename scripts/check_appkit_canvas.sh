#!/usr/bin/env bash
# Compile and validate the custom-painted AppKit product without opening a window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "appkit canvas: skipped (not macOS)"
  exit 0
fi

bash "$ROOT/scripts/build_appkit_canvas.sh" hello >/dev/null
BIN="$ROOT/build/hello_appkit_canvas"
APP="$ROOT/build/hello_appkit_canvas.app"
SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/elisa-ui-canvas.XXXXXX.png")"
trap 'rm -f "$SNAPSHOT"' EXIT
BRIDGE_TEST="$ROOT/build/appkit_canvas_bridge_test"

# Architecture guard: headless/test configuration belongs to Elisa. The Cocoa
# shim receives explicit values and must not silently grow a second policy path.
if grep -Eq 'getenv\("ELISA_UI_(SMOKE_FRAMES|SNAPSHOT)"' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: environment policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'elisa_canvas_headless|elisaInteraction|elisa_appkit_canvas_(select_all|delete_selection|selected_text_pointer|selected_text_length|undo|redo)\b' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: framework state or edit policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'elisa_appkit_canvas_(clear|rect|circle|triangle|line|render_options)\b' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: CoreGraphics path rendering leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'elisa_appkit_canvas_text(_width)?\b' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: CoreText text rendering leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq '\bNSFont\b|NSForegroundColorAttributeName|sizeWithAttributes' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: font construction or measurement leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq '\bvalueKind\b|\bvalue_kind\b' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: accessibility value-shape policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'modifiers[[:space:]]*&[[:space:]]*[1248]' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: menu modifier policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'notifications[[:space:]]*&[[:space:]]*[124]' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: accessibility notification policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq '\bappendApplicationName\b' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: menu title policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'elisa_menu_action|elisa_text_action|int[[:space:]]+token[[:space:]]*=' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: selector/action policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'modifierFlags[[:space:]]*&|flags[[:space:]]*&' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: modifier decoding leaked back into Objective-C" >&2
  exit 1
fi

# These callbacks cross the Objective-C/Elisa boundary and must survive dead
# stripping in the packaged product.
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_frame$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_raw_key$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_raw_flags$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_key_down_route$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_key_up$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_focus_changed$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_environment_changed$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_text_selector$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menus_begin$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menu_add_item$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menu_add_application_item$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menus_commit$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_activate$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_adjust$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_cancel_interaction$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_allows_text_readback$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_cursor_at$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_text_click$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_set_text$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_selection_location$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_set_selected_range$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_marked_location$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_commit_text$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_update_marked_text$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_text_action_enabled$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_perform_text_action$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_clipboard_write$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_clipboard_read$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_character_x$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_character_at_x$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_range_pointer$'
nm -g "$BIN" | grep -q ' U _clock_gettime_nsec_np$'
if nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_\(monotonic_time\|set_shadow\)$'; then
  echo "appkit canvas: time or shadow policy leaked back into Objective-C" >&2
  exit 1
fi
nm -g "$BIN" | grep -q ' U _CTFontCreateUIFontForLanguage$'
nm -g "$BIN" | grep -q ' U _CTFontGetAscent$'
nm -g "$BIN" | grep -q ' U _CTLineDraw$'
nm -g "$BIN" | grep -q ' U _CTLineGetTypographicBounds$'
nm -g "$BIN" | grep -q ' U _CFStringCreateWithBytes$'
nm -g "$BIN" | grep -q ' U _CGColorCreateGenericRGB$'
if nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_\(line_height\|ascent\)$'; then
  echo "appkit canvas: font metrics leaked back into Objective-C" >&2
  exit 1
fi
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_schedule_redraw$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_present_headless$'
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"
ELISA_UI_SMOKE_FRAMES=1 ELISA_UI_SNAPSHOT="$SNAPSHOT" "$BIN"
[[ -s "$SNAPSHOT" ]]
file "$SNAPSHOT" | grep -q 'PNG image data, 800 x 680'
clang -fobjc-arc -Wall -Wextra -Werror -o "$BRIDGE_TEST" \
  "$ROOT/test/appkit_canvas_bridge_test.m" -framework Cocoa
"$BRIDGE_TEST"
echo "appkit canvas: build, off-screen PNG frame, semantic bridge, callbacks, bundle and signature passed"
