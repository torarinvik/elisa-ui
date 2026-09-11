#!/usr/bin/env bash
# Build the hosted package and inspect it without invoking Elisa,
# wasm-component-ld, or a windowing runtime. The inspection itself is
# compiler-independent: it proves the artifact carries the public profile and
# the guest/host contract.
#
# IT BUILDS FIRST, AND IT IS IN THE SUITE. Neither was true before. run_tests.sh
# never called this gate, so the WasmBrowser target sat outside every green run
# the way Android once did -- and the gate inspected whatever .wapp happened to
# be in build/, which on the machine that found this was three days old. A pass
# then meant the package had been right in the state the tree used to be in.
#
# WHAT IT FOUND THE FIRST TIME IT ACTUALLY BUILT (2026-09-11), because this is
# the kind of thing a stale artifact hides:
#   1. initial linear memory had outgrown 32 pages -- fixed here, in
#      build_wapp.sh, and the data segments are why a growing heap does not
#      cover it;
#   2. the link then fails on `env::ctx_string_views_eq`, the runtime helper a
#      match over string views compiles to. The NATIVE runtime object defines
#      it; the wasm one does not, and --allow-undefined cannot help because
#      component validation rejects the leftover `env` import. That is the
#      compiler repo's gap, not this one's -- writing a stand-in for a
#      compiler-internal ABI symbol here is the same mistake as writing the
#      Windows runtime host in this repo.
# So this gate is red until that is answered, and red is the correct colour: it
# has been broken since about 2026-09-10 and nothing said so.
#
# It SKIPS, rather than failing, when a prerequisite is absent: the sibling
# WasmBrowser checkout, its CLI, or the wasm SDK. A missing toolchain is
# unknown, not passed, and the skip line says which piece is missing. Pass a
# package path to inspect that file as given and skip the build.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GIVEN_PACKAGE="${1:-}"
PACKAGE="${GIVEN_PACKAGE:-$ROOT/build/hello.wapp}"
WASMBROWSER="${ELISA_UI_WASMBROWSER:-$ROOT/../WasmBrowser}"
WASM_SDK="${ELISA_UI_WASM_SDK:-$ROOT/../wasm-sdk}"
WASM_BROWSER_CLI="${WASM_BROWSER_CLI:-}"
CLI_COMPONENT="${WASMBROWSER_ELISA_CLI_COMPONENT:-$WASMBROWSER/build/wasmbrowser-cli.wasm}"

if [[ -z "$WASM_BROWSER_CLI" ]] && command -v wasm-browser >/dev/null 2>&1; then
  WASM_BROWSER_CLI="$(command -v wasm-browser)"
fi
for candidate in "$WASMBROWSER/target/debug/wasm-browser" "$WASMBROWSER/target/release/wasm-browser"; do
  [[ -z "$WASM_BROWSER_CLI" && -x "$candidate" ]] && WASM_BROWSER_CLI="$candidate"
done
[[ -x "$WASM_BROWSER_CLI" ]] || {
  echo "wapp: skipped (no wasm-browser CLI; build it in $WASMBROWSER or set WASM_BROWSER_CLI)"; exit 0; }
[[ -f "$CLI_COMPONENT" ]] || {
  echo "wapp: skipped (no Elisa CLI component at $CLI_COMPONENT)"; exit 0; }

# Build the package under inspection, so the gate reports on this tree rather
# than on whatever was left in build/. An explicitly named package is inspected
# as given -- that is the form a person uses to ask about one particular file.
if [[ -z "$GIVEN_PACKAGE" ]]; then
  if [[ ! -f "$WASM_SDK/sdk/elisa/wasmbrowser/host_bindings.elisa" ]]; then
    echo "wapp: skipped (no wasm SDK bindings at $WASM_SDK; set ELISA_UI_WASM_SDK)"; exit 0
  fi
  if [[ ! -f "${ELISA_UI_WIT:-$WASMBROWSER/wit/wasmbrowser.wit}" ]]; then
    echo "wapp: skipped (no WasmBrowser WIT world; set ELISA_UI_WIT)"; exit 0
  fi
  bash "$ROOT/scripts/build_wapp.sh" hello >/dev/null
fi
[[ -f "$PACKAGE" ]] || { echo "wapp: the build produced no package at $PACKAGE" >&2; exit 1; }

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

echo "wapp: built from this tree; profile, imports and exports inspected and JS-free"
