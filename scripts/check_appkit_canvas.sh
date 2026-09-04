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
if grep -Eq 'if[[:space:]]*\([[:space:]]*tooltip[[:space:]]*\)' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: accessibility tooltip policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq '\bappendApplicationName\b' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: menu title policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'stringWithFormat:@"elisa-ui-' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: accessibility identifier policy leaked back into Objective-C" >&2
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
if grep -Eq 'setActivationPolicy:.*\?|setTabbingMode:.*\?' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: activation or tabbing policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'if \(layoutChanged\)' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: accessibility layout-notification policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'if \(delay <= 0\.0f\)' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: redraw cancellation policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'forMode:NSRunLoopCommonModes' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: run-loop mode policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'backing:NSBackingStoreBuffered' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: backing-store policy leaked back into Objective-C constructors" >&2
  exit 1
fi
if grep -Eq 'forType:NSPasteboardTypeString|stringForType:NSPasteboardTypeString|colorSpaceName:NSCalibratedRGBColorSpace|representationUsingType:NSBitmapImageFileTypePNG' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: pasteboard or snapshot encoding policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'if \(activate\)' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: visible activation policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'if \(centered\)' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: window centering policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'elisa_appkit_canvas_pointer\(' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: pointer event-kind policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'elisa_appkit_canvas_arrow_cursor\(\)[[:space:]]*set' "$ROOT/src/platform/appkit/appkit_canvas_shim.m"; then
  echo "appkit canvas: leave-cursor policy leaked back into Objective-C" >&2
  exit 1
fi

# These callbacks cross the Objective-C/Elisa boundary and must survive dead
# stripping in the packaged product.
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_frame$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_pointer_move$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_pointer_down$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_pointer_up$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_pointer_leave$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_pointer_scroll$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_cursor_leave$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_window_style_titled$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_window_style_closable$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_window_style_miniaturizable$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_window_style_resizable$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_backing_store_buffered$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_pasteboard_type_string$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_bitmap_color_space_calibrated_rgb$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_bitmap_file_type_png$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_activation_policy_regular$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_activation_policy_prohibited$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_tabbing_mode_preferred$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_tabbing_mode_disallowed$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_tracking_mouse_moved$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_tracking_mouse_entered_exited$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_tracking_active_in_key_window$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_tracking_in_visible_rect$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_run_loop_common_modes$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_key_down_event$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_raw_flags$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_key_up$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_focus_changed$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_environment_changed$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_text_selector$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menus_begin$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menu_add_item$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_menus_commit$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_activate$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_adjust$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_add_tooltip$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_commit$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_layout_changed_notification$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_accessibility_post_layout_changed$'
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
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_cancel_redraw$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_activate$'
nm -g "$BIN" | grep -q ' T _elisa_appkit_canvas_center$'
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
