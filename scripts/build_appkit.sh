#!/usr/bin/env bash
# Build the AppKit example: a real macOS app driven by the widget tree.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# A DIRECTORY OF ITS OWN, so two scripts cannot write one object path. Same
# reason as the Skia shims: a shared $ROOT/build name is a race between gates
# that a suite runs in sequence and a person runs one at a time.
GATE_OBJ_DIR="$ROOT/build/appkit"
mkdir -p "$GATE_OBJ_DIR"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
EXAMPLE="${1:-hello}"

[[ "$(uname -s)" == "Darwin" ]] || { echo "the AppKit backend is macOS only" >&2; exit 2; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }

mkdir -p "$ROOT/build"
clang -c -fobjc-arc -o "$GATE_OBJ_DIR/appkit_shim.o" "$ROOT/src/platform/appkit/appkit_shim.m"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/${EXAMPLE}_appkit.o" "$ROOT/examples/$EXAMPLE/appkit_main.elisa"
clang -Wl,-dead_strip -o "$ROOT/build/${EXAMPLE}_appkit" \
  "$ROOT/build/${EXAMPLE}_appkit.o" "$GATE_OBJ_DIR/appkit_shim.o" "$RUNTIME" -framework Cocoa
echo "built $ROOT/build/${EXAMPLE}_appkit"
