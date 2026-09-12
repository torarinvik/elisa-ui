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

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$ROOT/build"

# The Elisa side: ui_capi supplies the host-facing functions, ui_capi_app
# supplies the app contract and forwards to the elisa_ui_on_* callbacks the
# Rust example implements. `include` resolves relative to the including file,
# so build it in place.
cat > "$WORK/bridge.elisa" <<'EOF'
include "../src/capi/ui_capi.elisa"
include "../src/capi/ui_capi_app.elisa"
EOF
cp "$WORK/bridge.elisa" "$ROOT/build/rust_bridge_link.elisa"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/bridge.o" "$ROOT/build/rust_bridge_link.elisa"
rm -f "$ROOT/build/rust_bridge_link.elisa"

rustc --edition 2021 -O "$ROOT/examples/rust/rust_host.rs" -o "$WORK/rust_host" \
  -C link-arg="$WORK/bridge.o" -C link-arg="$RUNTIME"
"$WORK/rust_host"
