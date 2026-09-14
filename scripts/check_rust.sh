#!/usr/bin/env bash
# Build and run the Rust host example against the real Elisa C boundary.
#
# The C boundary is the contract two languages share, and nothing else checks
# that the Rust face of it agrees with the header: the Elisa suite never sees
# Rust, and the C example never sees Rust. This links and runs a safe wrapper
# over the same ABI, including borrowed UTF-8 text and opaque widget handles.
#
# Skips itself when no Rust toolchain is installed; a missing toolchain is
# unknown, not passed.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"

command -v rustc >/dev/null 2>&1 || { echo "rust: skipped (no rustc on PATH)"; exit 0; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME" >&2; exit 2; }

mkdir -p "$ROOT/build"
WORK="$(mktemp -d "$ROOT/build/rust-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# Compile the binding as a separate crate so these checks exercise the public
# surface exactly as a downstream Rust application sees it. The token may be
# wrapped at the callback boundary, but tuple construction and representation
# access must stay private.
rustc --edition 2021 --crate-name elisa_ui --crate-type rlib \
  "$ROOT/bindings/rust/elisa_ui.rs" -o "$WORK/libelisa_ui.rlib"
rustc --edition 2021 "$ROOT/test/rust_widget_handle_api.rs" \
  --extern "elisa_ui=$WORK/libelisa_ui.rlib" -o "$WORK/widget_handle_api"
"$WORK/widget_handle_api"

for fixture in rust_widget_handle_private_field rust_widget_handle_private_constructor; do
  if rustc --edition 2021 "$ROOT/test/$fixture.rs" \
    --extern "elisa_ui=$WORK/libelisa_ui.rlib" -o "$WORK/$fixture" \
    >"$WORK/$fixture.log" 2>&1; then
    echo "rust: $fixture unexpectedly compiled" >&2
    exit 1
  fi
  if ! grep -qi "private" "$WORK/$fixture.log"; then
    echo "rust: $fixture failed for a reason other than handle opacity" >&2
    sed -n '1,80p' "$WORK/$fixture.log" >&2
    exit 1
  fi
done
echo "rust: widget handle opacity passed"

# The Elisa side: ui_capi supplies the host-facing functions, ui_capi_app
# supplies the app contract and forwards to the elisa_ui_on_* callbacks the
# Rust example implements. `include` resolves relative to the including file;
# this unique temporary source lives under build/ so the paths reach src/ without
# borrowing a fixed path another check or user may already own.
cat > "$WORK/bridge.elisa" <<'EOF'
include "../../src/capi/ui_capi.elisa"
include "../../src/capi/ui_capi_app.elisa"
EOF
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/bridge.o" "$WORK/bridge.elisa"

rustc --edition 2021 -O "$ROOT/examples/rust/rust_host.rs" -o "$WORK/rust_host" \
  -C link-arg="$WORK/bridge.o" -C link-arg="$RUNTIME"
"$WORK/rust_host"
