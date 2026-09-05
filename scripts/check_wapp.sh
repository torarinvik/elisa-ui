#!/usr/bin/env bash
# Inspect an already-built .wapp without invoking Elisa, wasm-component-ld, or
# a windowing runtime. This is the compiler-independent hosted package fixture:
# it proves the artifact carries the public profile and guest/host contract.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${1:-$ROOT/build/hello.wapp}"
WASMBROWSER="${ELISA_UI_WASMBROWSER:-$ROOT/../WasmBrowser}"
WASM_BROWSER_CLI="${WASM_BROWSER_CLI:-}"
CLI_COMPONENT="${WASMBROWSER_ELISA_CLI_COMPONENT:-$WASMBROWSER/build/wasmbrowser-cli.wasm}"

[[ -f "$PACKAGE" ]] || { echo "missing package: $PACKAGE (run scripts/build_wapp.sh first)" >&2; exit 2; }
if [[ -z "$WASM_BROWSER_CLI" ]] && command -v wasm-browser >/dev/null 2>&1; then
  WASM_BROWSER_CLI="$(command -v wasm-browser)"
fi
for candidate in "$WASMBROWSER/target/debug/wasm-browser" "$WASMBROWSER/target/release/wasm-browser"; do
  [[ -z "$WASM_BROWSER_CLI" && -x "$candidate" ]] && WASM_BROWSER_CLI="$candidate"
done
[[ -x "$WASM_BROWSER_CLI" ]] || { echo "wasm-browser CLI not found; set WASM_BROWSER_CLI" >&2; exit 2; }
[[ -f "$CLI_COMPONENT" ]] || { echo "missing Elisa CLI component: $CLI_COMPONENT" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-wapp-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
WASMBROWSER_ELISA_CLI_COMPONENT="$CLI_COMPONENT" \
  "$WASM_BROWSER_CLI" inspect "$PACKAGE" >"$WORK/inspect.log"

required=(
  "runtime profile: wasmbrowser:component@1"
  "language: elisa"
  "framework: elisa-ui"
  "format: component"
  "wasmbrowser:window/host@0.1.0::present-commands"
  "wasmbrowser:window/host@0.1.0::measure-text-width"
  "wasmbrowser:window/host@0.1.0::clipboard-get"
  "wasmbrowser:window/guest@0.1.0#start"
  "wasmbrowser:window/guest@0.1.0#frame"
  "wasmbrowser:window/guest@0.1.0#pointer-button-input"
)
for marker in "${required[@]}"; do
  rg -Fq "$marker" "$WORK/inspect.log" || { echo "hosted package is missing: $marker" >&2; exit 1; }
done
if rg -i -q '(^|[^[:alnum:]_])(javascript|typescript|\.js|\.ts|esm)([^[:alnum:]_]|$)' "$WORK/inspect.log"; then
  echo "hosted package inspection mentioned a forbidden JS/TS/ESM artifact" >&2
  exit 1
fi

echo "hosted package: compiler-independent profile/import/export inspection passed"
