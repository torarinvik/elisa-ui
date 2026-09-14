#!/usr/bin/env bash
# Run the retained-tree performance fixture without opening a window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
PROCESS_REPETITIONS="${ELISA_UI_PERF_PROCESS_REPETITIONS:-3}"
REQUIRE_BUDGET="${ELISA_UI_REQUIRE_PERF_BUDGET:-0}"
ELISA_FLAGS=(-O2)
C_FLAGS=(-O0 -std=c11 -Wall -Wextra -Werror)
LINK_FLAGS=(-Wl,-dead_strip)

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "performance: no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "performance: no runtime object at $RUNTIME" >&2; exit 2; }
[[ "$PROCESS_REPETITIONS" =~ ^[1-9][0-9]*$ ]] && (( PROCESS_REPETITIONS <= 10 )) || {
    echo "performance: ELISA_UI_PERF_PROCESS_REPETITIONS must be an integer in 1..10" >&2
    exit 2
}
[[ "$REQUIRE_BUDGET" == 0 || "$REQUIRE_BUDGET" == 1 ]] || {
    echo "performance: ELISA_UI_REQUIRE_PERF_BUDGET must be 0 or 1" >&2
    exit 2
}

ELISA_UI_STAGE1="$STAGE1" bash "$ROOT/scripts/check_toolchain.sh"
ELISA_UI_STAGE1="$STAGE1" python3 "$ROOT/test/performance_budget_test.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-performance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

bash "$STAGE1/scripts/elisac_stage1.sh" "${ELISA_FLAGS[@]}" -o "$WORK/benchmark.o" "$ROOT/test/performance_benchmark.elisa"
clang "${C_FLAGS[@]}" -c "$ROOT/test/performance_benchmark.c" -o "$WORK/benchmark.c.o"
clang "${LINK_FLAGS[@]}" -o "$WORK/performance_benchmark" "$WORK/benchmark.c.o" "$WORK/benchmark.o" "$RUNTIME"

RUN_LOG="$WORK/run.log"
: >"$RUN_LOG"
for ((index = 0; index < PROCESS_REPETITIONS; ++index)); do
    "$WORK/performance_benchmark" >>"$RUN_LOG" 2>&1 || {
        cat "$RUN_LOG"
        exit 1
    }
done
cat "$RUN_LOG"

budget_args=(
    --root "$ROOT"
    --stage1 "$STAGE1"
    --log "$RUN_LOG"
    --manifest "$ROOT/test/performance_budgets.json"
    --process-repetitions "$PROCESS_REPETITIONS"
    "--elisa-flags=${ELISA_FLAGS[*]}"
    "--c-flags=${C_FLAGS[*]}"
    "--link-flags=${LINK_FLAGS[*]}"
)
[[ "$REQUIRE_BUDGET" == 1 ]] && budget_args+=(--require-budget)
python3 "$ROOT/scripts/check_performance_budget.py" "${budget_args[@]}"
