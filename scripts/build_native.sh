#!/usr/bin/env bash
# Build the native hello example with the elisa-ui stage1 worktree compiler.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../elisa-ui-worktrees/stage1}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
SDL_LIB="${ELISA_UI_SDL_LIB:-/opt/homebrew/lib}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1 (run scripts/elisac_stage1.sh --seed there)" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME (run scripts/build_runtime_object.sh there)" >&2; exit 2; }

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/hello_native.o" "$ROOT/examples/hello/native_main.elisa"
clang -Wl,-dead_strip -o "$ROOT/build/hello_native" "$ROOT/build/hello_native.o" "$RUNTIME" -L"$SDL_LIB" -lSDL3 -lSDL3_ttf -Wl,-rpath,"$SDL_LIB"
echo "built $ROOT/build/hello_native"
