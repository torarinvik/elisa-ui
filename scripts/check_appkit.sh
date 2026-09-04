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
if grep -Eq 'styleMask:[[:space:]]*\(NSWindowStyleMask(Titled|Closable|Miniaturizable|Resizable|UtilityWindow)|setBezelStyle:NSBezelStyleRounded|setButtonType:NSButtonTypePushOnPushOff|setStyle:NSProgressIndicatorStyleBar' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: native control style policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'setActivationPolicy:NSApplicationActivationPolicyRegular' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: activation policy leaked back into Objective-C initialization" >&2
  exit 1
fi
if grep -Eq 'ELISA_APPKIT_MAX|static id elisa_objects\[' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: native object-table capacity was duplicated in Objective-C" >&2
  exit 1
fi
if grep -Eq 'static NSWindow \*elisa_window' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: root-window state was duplicated outside the Elisa control table" >&2
  exit 1
fi
if ! grep -Eq 'void elisa_appkit_init\(void\)' "$ROOT/src/platform/appkit/appkit_shim.m" || \
   ! grep -Eq 'elisa_appkit_init\(\)' "$ROOT/src/platform/appkit/ui_appkit.elisa"; then
  echo "appkit: native object-table reset did not remain a narrow FFI primitive" >&2
  exit 1
fi
if grep -Eq 'sliderWithValue:0 minValue:0 maxValue:1' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: slider state defaults leaked back into Objective-C constructors" >&2
  exit 1
fi
if grep -Eq 'setFloatingPanel:YES|setBecomesKeyOnlyIfNeeded:YES' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: panel behavior policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'backing:NSBackingStoreBuffered' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: backing-store policy leaked back into Objective-C constructors" >&2
  exit 1
fi
if grep -Eq 'NSUTF8StringEncoding|initWithBytes:' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: control text conversion leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'stringWithUTF8String:' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: class-name text conversion leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq '@""' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: empty control text leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq 'NSMakeRect\(0, 0, (640, 480|480, 320)\)' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: bootstrap window sizing policy leaked back into Objective-C" >&2
  exit 1
fi
if grep -Eq '\- \(BOOL\)isFlipped \{ return YES; \}' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: coordinate orientation policy leaked back into Objective-C" >&2
  exit 1
fi
if awk '/void elisa_appkit_present\(void\)/ { inside=1 } inside && /activateIgnoringOtherApps:YES/ { found=1 } inside && /^}/ { inside=0 } END { exit found ? 0 : 1 }' "$ROOT/src/platform/appkit/appkit_shim.m"; then
  echo "appkit: visible activation policy leaked back into Objective-C" >&2
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
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_bezel_style_rounded$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_button_type_push_on_push_off$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_control_state_on$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_control_state_off$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_progress_style_bar$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_backing_store_buffered$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_activation_policy_regular$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_activation_policy$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_window_with_style$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_panel_window$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_create_scroll_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_view_is_flipped$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_scroll_document_frame$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_attach_to_window$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_attach_to_scroll_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_attach_to_view$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_button_state$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_slider_state$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_set_progress_value$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_button_bezel_style$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_button_toggles$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_panel_becomes_key_only$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_progress_style$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_progress_is_indeterminate$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_scroll_has_vertical$'
nm -g "$ROOT/build/appkit_check" | grep -q ' T _elisa_appkit_scroll_has_horizontal$'
if nm -g "$ROOT/build/appkit_check" | grep -Eq ' T _elisa_appkit_(create|set_(text|frame))$'; then
  echo "appkit: obsolete generic entry point survived the link" >&2
  exit 1
fi
if nm -g "$ROOT/build/appkit_check" | grep -Eq ' T _elisa_appkit_create_(fixed_window|resizable_window|window)$'; then
  echo "appkit: undifferentiated window creation survived the link" >&2
  exit 1
fi
"$ROOT/build/appkit_check"
