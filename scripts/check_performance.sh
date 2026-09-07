#!/usr/bin/env bash
# Run the retained-tree performance fixture without opening a window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "performance: no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "performance: no runtime object at $RUNTIME" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-performance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

bash "$STAGE1/scripts/elisac_stage1.sh" -O2 -o "$WORK/benchmark.o" "$ROOT/test/performance_benchmark.elisa"
clang -std=c11 -Wall -Wextra -Werror -c "$ROOT/test/performance_benchmark.c" -o "$WORK/benchmark.c.o"
clang -Wl,-dead_strip -o "$WORK/performance_benchmark" "$WORK/benchmark.c.o" "$WORK/benchmark.o" "$RUNTIME"
"$WORK/performance_benchmark"
