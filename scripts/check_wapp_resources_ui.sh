#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${WASM_SDK_ROOT:-$ROOT/../wasm-sdk}"
BROWSER_ROOT="${WASMBROWSER_ROOT:-$ROOT/../WasmBrowser}"
if [[ -n "${ELISA_COMPILER_ROOT:-}" ]]; then
  COMPILER_ROOT="$ELISA_COMPILER_ROOT"
elif [[ -n "${ELISA_COMPILER_DIR:-}" ]]; then
  COMPILER_ROOT="$ELISA_COMPILER_DIR"
elif [[ -n "${ELISA_UI_STAGE1:-}" ]]; then
  COMPILER_ROOT="$ELISA_UI_STAGE1"
else
  COMPILER_ROOT="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
fi
STAGE1="${ELISAC_STAGE1:-$COMPILER_ROOT/scripts/elisac_stage1.sh}"
WIT="$SDK_ROOT/wit/resources/wasmbrowser.resources.wit"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-wasm-resources.XXXXXX")"
OUTPUT="$WORK/ui-resources-component.wasm"
trap 'rm -rf -- "$WORK"' EXIT INT TERM HUP

[[ -x "$STAGE1" ]] || { echo "resource UI smoke: missing Stage1 at $STAGE1" >&2; exit 2; }
if [[ ! -f "$WIT" ]]; then
  echo "resource UI smoke: skipped (missing resources WIT at $WIT)" >&2
  exit 0
fi
if [[ ! -d "$SDK_ROOT/sdk/elisa/wasmbrowser/resources" || ! -f "$SDK_ROOT/sdk/elisa/wasmbrowser/resources.elisa" || ! -f "$SDK_ROOT/sdk/elisa/wasmbrowser/operations.elisa" || ! -f "$SDK_ROOT/sdk/elisa/wasmbrowser/memory_boundary.elisa" || ! -f "$SDK_ROOT/sdk/elisa/wasmbrowser/canonical_result.elisa" || ! -f "$SDK_ROOT/tools/wasmbrowser_profiles.py" || ! -f "$SDK_ROOT/tools/wasmbrowser_bindings.py" || ! -f "$SDK_ROOT/contracts/wasmbrowser-resources.contract.json" ]]; then
  echo "resource UI smoke: skipped (incomplete WasmBrowser SDK profile at $SDK_ROOT)" >&2
  exit 0
fi
if [[ -z "${WASM_BROWSER_VALIDATOR_BIN:-}" && ! -f "$BROWSER_ROOT/Cargo.toml" ]]; then
  echo "resource UI smoke: skipped (missing WasmBrowser checkout at $BROWSER_ROOT)" >&2
  exit 0
fi
if [[ -z "${WASM_BROWSER_VALIDATOR_BIN:-}" && -z "${WASM_BROWSER_RUSTUP_TOOLCHAIN:-}" ]] && ! command -v cargo >/dev/null 2>&1; then
  echo "resource UI smoke: skipped (Cargo unavailable)" >&2
  exit 0
fi
if [[ -n "${WASM_BROWSER_RUSTUP_TOOLCHAIN:-}" ]] && ! command -v rustup >/dev/null 2>&1; then
  echo "resource UI smoke: rustup toolchain selected but rustup is unavailable" >&2
  exit 2
fi

PROFILE_ROOT="$WORK/wasm-sdk/sdk/elisa/wasmbrowser/resources"
mkdir -p "$PROFILE_ROOT" "$WORK/elisa-ui"
cp -R "$SDK_ROOT/sdk/elisa/wasmbrowser/resources/." "$PROFILE_ROOT/"
cp "$SDK_ROOT/sdk/elisa/wasmbrowser/resources.elisa" "$PROFILE_ROOT/resource_model.elisa"
cp "$SDK_ROOT/sdk/elisa/wasmbrowser/operations.elisa" "$PROFILE_ROOT/operation_model.elisa"
cp "$SDK_ROOT/sdk/elisa/wasmbrowser/memory_boundary.elisa" "$PROFILE_ROOT/memory_boundary.elisa"
cp "$SDK_ROOT/sdk/elisa/wasmbrowser/canonical_result.elisa" "$PROFILE_ROOT/canonical_result.elisa"
cp "$ROOT/test/wasmbrowser_resources_ui_guest.elisa" "$PROFILE_ROOT/entry.elisa"
cp -R "$ROOT/src" "$WORK/elisa-ui/src"

python3 "$SDK_ROOT/tools/wasmbrowser_profiles.py" check \
  --sdk-root "$SDK_ROOT" --wit "$WIT" --profile wasmbrowser:resources@1
python3 "$SDK_ROOT/tools/wasmbrowser_bindings.py" verify \
  --wit "$WIT" --profile wasmbrowser:resources@1 \
  --lock "$SDK_ROOT/contracts/wasmbrowser-resources.contract.json" \
  --sdk-root "$PROFILE_ROOT" --recursive

ELISA_ALLOW_STALE_STAGE1="${ELISA_ALLOW_STALE_STAGE1:-0}" \
  "$STAGE1" -emit wasm --wasm-only --component-type "$WIT" -O0 -o "$OUTPUT" "$PROFILE_ROOT/entry.elisa"

if [[ -n "${WASM_BROWSER_VALIDATOR_BIN:-}" ]]; then
  [[ -x "$WASM_BROWSER_VALIDATOR_BIN" ]] || {
    echo "resource UI smoke: validator is not executable: $WASM_BROWSER_VALIDATOR_BIN" >&2
    exit 2
  }
  "$WASM_BROWSER_VALIDATOR_BIN" "$OUTPUT"
else
  (
    cd "$BROWSER_ROOT"
    if [[ -n "${WASM_BROWSER_RUSTUP_TOOLCHAIN:-}" ]]; then
      selected_rustc="${RUSTC:-$(rustup which rustc --toolchain "$WASM_BROWSER_RUSTUP_TOOLCHAIN")}"
      RUSTC="$selected_rustc" \
        rustup run "$WASM_BROWSER_RUSTUP_TOOLCHAIN" cargo run --locked -q -p wb-runtime --example validate_resource_component -- "$OUTPUT"
    else
      cargo run --locked -q -p wb-runtime --example validate_resource_component -- "$OUTPUT"
    fi
  )
fi

echo "WasmBrowser UI resource smoke OK: asset operation updated the generation-safe UiResources lifecycle" >&2
