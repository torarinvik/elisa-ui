#!/usr/bin/env bash
# Build the hello example as a WasmBrowser .wapp package.
#
# Two steps, mirroring WasmBrowser's own SDK recipe: compile the Elisa sources
# into a Wasm component against the WIT world, then pack manifest.json + the
# component. No JavaScript, ESM loader, or TypeScript facade is produced at any
# point -- --component-type implies --wasm-only.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
WASMBROWSER="${ELISA_UI_WASMBROWSER:-$ROOT/../WasmBrowser}"
WIT="${ELISA_UI_WIT:-$WASMBROWSER/wit/wasmbrowser.wit}"
EXAMPLE="${1:-hello}"
OUTPUT="${2:-$ROOT/build/$EXAMPLE.wapp}"
WASM_INITIAL_PAGES="${ELISA_UI_WASM_INITIAL_PAGES:-32}"
WASM_MAX_PAGES="${ELISA_UI_WASM_MAX_PAGES:-32768}"

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1 (run scripts/elisac_stage1.sh --seed there)" >&2; exit 2; }
[[ -f "$WIT" ]] || { echo "missing WasmBrowser WIT: $WIT (set ELISA_UI_WIT or ELISA_UI_WASMBROWSER)" >&2; exit 2; }
[[ -f "$ROOT/examples/$EXAMPLE/wapp_main.elisa" ]] || { echo "no component entry: examples/$EXAMPLE/wapp_main.elisa" >&2; exit 2; }

mkdir -p "$ROOT/build"

# Stage the package in a temp directory so generated binaries never land in the
# source tree; the only payload is manifest.json and main.wasm.
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-wapp.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT INT TERM HUP
cp "$ROOT/examples/$EXAMPLE/manifest.json" "$PACKAGE_DIR/manifest.json"

# The flat retained layer keeps text, secure-text, and edit-history storage in
# static linear memory. Pass its package-sized heap policy to stage1 rather than
# reducing those capacities just to fit the compiler's historical 1 MiB default.
ELISA_WASM_INITIAL_PAGES="$WASM_INITIAL_PAGES" \
ELISA_WASM_MAX_PAGES="$WASM_MAX_PAGES" \
  bash "$STAGE1/scripts/elisac_stage1.sh" \
  -emit wasm \
  --wasm-only \
  --component-type "$WIT" \
  -o "$PACKAGE_DIR/main.wasm" \
  "$ROOT/examples/$EXAMPLE/wapp_main.elisa"

# Keep the raw component next to the package for inspection and smoke checks.
cp "$PACKAGE_DIR/main.wasm" "$ROOT/build/$EXAMPLE.wasm"

WASM_BROWSER_CLI="${WASM_BROWSER_CLI:-}"
if [[ -z "$WASM_BROWSER_CLI" ]] && command -v wasm-browser >/dev/null 2>&1; then
  WASM_BROWSER_CLI="$(command -v wasm-browser)"
fi
for candidate in "$WASMBROWSER/target/debug/wasm-browser" "$WASMBROWSER/target/release/wasm-browser"; do
  [[ -z "$WASM_BROWSER_CLI" && -x "$candidate" ]] && WASM_BROWSER_CLI="$candidate"
done

if [[ -z "$WASM_BROWSER_CLI" ]]; then
  echo "built component $ROOT/build/$EXAMPLE.wasm"
  echo "WasmBrowser CLI not found; set WASM_BROWSER_CLI or run 'cargo build -p wb-cli' in $WASMBROWSER to pack the .wapp" >&2
  exit 3
fi

# The Rust CLI resolves its Elisa command component relative to the current
# directory by default. Point it at the WasmBrowser checkout explicitly so this
# project can be built from any working directory (and so a custom component
# remains possible through the documented environment variable).
WASMBROWSER_ELISA_CLI_COMPONENT="${WASMBROWSER_ELISA_CLI_COMPONENT:-$WASMBROWSER/build/wasmbrowser-cli.wasm}" \
  "$WASM_BROWSER_CLI" pack "$PACKAGE_DIR" -o "$OUTPUT"
echo "built $OUTPUT"
