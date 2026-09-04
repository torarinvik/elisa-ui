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
clang -c -fobjc-arc -o "$ROOT/build/appkit_shim.o" "$ROOT/src/platform/appkit/appkit_shim.m"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/appkit_check.o" "$ROOT/src/platform/appkit/appkit_check.elisa"
clang -Wl,-dead_strip -o "$ROOT/build/appkit_check" \
  "$ROOT/build/appkit_check.o" "$ROOT/build/appkit_shim.o" "$RUNTIME" -framework Cocoa
"$ROOT/build/appkit_check"
