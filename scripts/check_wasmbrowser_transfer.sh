#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
WASM_SDK="${ELISA_UI_WASM_SDK:-$ROOT/../wasm-sdk}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "WasmBrowser transfer: missing Stage1 product" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "WasmBrowser transfer: missing Stage1 runtime object" >&2; exit 2; }
[[ -f "$WASM_SDK/sdk/elisa/wasmbrowser/host_bindings.elisa" ]] || {
  echo "WasmBrowser transfer: skipped (missing WasmBrowser SDK bindings at $WASM_SDK)"
  exit 0
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-wasm-transfer.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT INT TERM HUP
mkdir -p "$WORK/source/elisa-ui/src" "$WORK/source/elisa-ui/examples/hello"
cp -R "$ROOT/src/." "$WORK/source/elisa-ui/src/"
cp "$ROOT/test/wasmbrowser_transfer_fixture.elisa" "$WORK/source/elisa-ui/examples/hello/"
ln -s "$WASM_SDK/sdk" "$WORK/source/sdk"

ELISA_UI_STAGE1="$STAGE1" bash "$ROOT/scripts/check_toolchain.sh" --report >&2
ELISA_COMPILER_ROOT="$STAGE1" ELISA_COMPILER_DIR="$STAGE1" \
  bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/wasmbrowser_transfer.o" \
  "$WORK/source/elisa-ui/examples/hello/wasmbrowser_transfer_fixture.elisa"
clang -c -Wall -Wextra -Werror -o "$WORK/wasmbrowser_transfer_host.o" "$ROOT/test/wasmbrowser_transfer_host.c"
clang -Wl,-dead_strip -o "$WORK/wasmbrowser_transfer" \
  "$WORK/wasmbrowser_transfer.o" "$WORK/wasmbrowser_transfer_host.o" "$RUNTIME"
"$WORK/wasmbrowser_transfer"
