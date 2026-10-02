#!/usr/bin/env bash
# Exercise UIKit image-resource lifecycle policy independently of the full
# UIKit application, whose broad backend build can be blocked by unrelated
# current-Stage1 codegen declines.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no Stage1 compiler at $STAGE1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no Stage1 runtime at $RUNTIME" >&2; exit 2; }
ELISA_UI_STAGE1="$STAGE1" bash "$ROOT/scripts/check_toolchain.sh" --report >&2

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-uikit-image.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

"$STAGE1/bin/elisac-stage1" -emit obj -O0 -o "$WORK/uikit_image_upload_test.o" \
  "$ROOT/test/uikit_image_upload_test.elisa"
clang -Wl,-dead_strip -o "$WORK/uikit_image_upload_test" \
  "$WORK/uikit_image_upload_test.o" "$RUNTIME" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework ImageIO
"$WORK/uikit_image_upload_test"

if [[ "$(uname -s)" == "Darwin" ]] && SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)" && [[ -d "$SDK" ]]; then
  TRIPLE="$(uname -m)-apple-ios17.0-simulator"
  "$STAGE1/bin/elisac-stage1" -emit obj -O0 -target-triple "$TRIPLE" \
    -o "$WORK/uikit_image_upload_test_ios.o" "$ROOT/test/uikit_image_upload_test.elisa"
  file "$WORK/uikit_image_upload_test_ios.o" | grep -q 'Mach-O .* object' || {
    echo "UIKit image upload: expected a Mach-O simulator object" >&2
    exit 1
  }
  echo "UIKit image upload: simulator-target object compilation passed"
else
  echo "UIKit image upload: simulator-target compile skipped (iOS Simulator SDK unavailable)"
fi

echo "UIKit image upload: policy and binding-lifecycle gate passed"
