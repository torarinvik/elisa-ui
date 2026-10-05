#!/usr/bin/env bash
# Reproducible headless benchmark for the SDL3 text texture cache.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
SDL_LIB="${ELISA_UI_SDL_LIB:-/opt/homebrew/lib}"
LINKER_DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "text cache benchmark: no Stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "text cache benchmark: no runtime object at $RUNTIME" >&2; exit 2; }
[[ -f "$SDL_LIB/libSDL3.dylib" && -f "$SDL_LIB/libSDL3_ttf.dylib" ]] || {
    echo "text cache benchmark: SDL3 and SDL3_ttf are required in $SDL_LIB" >&2
    exit 2
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-sdl3-text-cache.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

DEVELOPER_DIR="$LINKER_DEVELOPER_DIR" "$STAGE1/scripts/elisac_stage1.sh" -O2 \
    -o "$WORK/benchmark.o" "$ROOT/test/sdl3_text_cache_benchmark.elisa"
clang -O2 -std=c11 -Wall -Wextra -Werror -c \
    "$ROOT/test/sdl3_text_cache_benchmark.c" -o "$WORK/benchmark.c.o"
DEVELOPER_DIR="$LINKER_DEVELOPER_DIR" clang -Wl,-dead_strip \
    -o "$WORK/sdl3_text_cache_benchmark" "$WORK/benchmark.c.o" \
    "$WORK/benchmark.o" "$RUNTIME" -L"$SDL_LIB" -lSDL3 -lSDL3_ttf \
    -Wl,-rpath,"$SDL_LIB"
"$WORK/sdl3_text_cache_benchmark"
