#!/usr/bin/env bash
# Validate the Skia custom painter without requiring a foregrounded window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || {
  echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2
  exit 2
}

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/ui_skia.o" "$ROOT/src/platform/skia/ui_skia.elisa"

if [[ -n "${SKIA_ROOT:-}" && -f "$SKIA_ROOT/include/core/SkCanvas.h" ]]; then
  echo "skia: Elisa painter compiles; SKIA_ROOT is available for the host shim"
else
  echo "skia: Elisa painter compiles; C++ shim deferred until SKIA_ROOT is configured"
fi
