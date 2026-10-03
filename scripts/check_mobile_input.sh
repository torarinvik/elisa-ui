#!/usr/bin/env bash
# Focused input acceptance; this does not replace the full renderer/device suite.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
STAGE1="$(bash scripts/resolve_stage1_root.sh "$ROOT")"
bash scripts/check_toolchain.sh
mkdir -p build
tests=(event_wire_test event_queue_test contact_event_test gestures_test
  mobile_contacts_test mobile_surface_test android_dispatch_test android_ime_ingress_test android_text_gesture_test
  mobile_focus_reveal_test retained_text_purpose_test text_input_test
  widget_handles_test widget_layout_geometry_test widget_layout_text_test
  text_lifecycle_workflow_test text_surrounding_test)
link_flags=(-Wl,--gc-sections)
if [[ "$(uname -s)" == Darwin ]]; then
  link_flags=(-Wl,-dead_strip)
  clang -c -Wall -Wextra -Werror -o build/uikit_host_stubs.o test/uikit_host_stubs.c
  tests+=(uikit_input_test uikit_surface_test uikit_text_input_test)
fi
for name in "${tests[@]}"; do
  bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "build/$name.o" "test/$name.elisa"
  inputs=("build/$name.o" "$STAGE1/build/runtime/elisacore_runtime.o")
  if [[ "$name" == uikit_* ]]; then
    inputs+=(build/uikit_host_stubs.o -framework CoreFoundation -framework CoreGraphics
      -framework CoreText -framework ImageIO)
  fi
  clang "${link_flags[@]}" -o "build/$name" "${inputs[@]}"
  "build/$name"
done
bash scripts/check_android_contacts.sh
bash scripts/check_android_ime_traits.sh
bash scripts/check_android_ime_windows.sh
bash scripts/check_android_ime_queue.sh
bash scripts/check_source_sizes.sh
bash scripts/check_global_names.sh
git diff --check
