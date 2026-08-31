#!/usr/bin/env bash
# Build the web hello example (wasm + generated loader) with the stage1 worktree compiler.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../elisa-ui-worktrees/stage1}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1 (run scripts/elisac_stage1.sh --seed there)" >&2; exit 2; }

mkdir -p "$ROOT/build"
bash "$STAGE1/scripts/elisac_stage1.sh" -emit wasm -o "$ROOT/build/hello_web.wasm" "$ROOT/examples/hello/web_main.elisa"
echo "built $ROOT/build/hello_web.wasm (+ .mjs loader); open examples/hello/index.html via a local server"
