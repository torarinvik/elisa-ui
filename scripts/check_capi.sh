#!/usr/bin/env bash
# Build a real C program against the library and run it.
#
# The header and the Elisa side are two hand-written descriptions of one ABI, and
# nothing else checks that they agree: the elisa suite never sees the header, and
# the header never sees the Elisa types. This links them and asserts a struct
# whose layout C computed reaches an Elisa function with its fields intact.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
mkdir -p "$ROOT/build"

# The Elisa side: both adapters at once, which also proves they can coexist.
cat > "$WORK/bridge.elisa" <<'EOF'
include "../src/capi/ui_capi.elisa"
include "../src/capi/ui_capi_app.elisa"
EOF
# `include` is resolved relative to the including file, so build it in place.
cp "$WORK/bridge.elisa" "$ROOT/build/capi_bridge_link.elisa"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/bridge.o" "$ROOT/build/capi_bridge_link.elisa"

clang -std=c11 -Wall -Wextra -I"$ROOT/include" \
  -c -o "$WORK/host.o" "$ROOT/examples/capi/c_host.c"
clang++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT/include" \
  -c -o "$WORK/header_cpp.o" "$ROOT/examples/capi/cpp_header_check.cc"
clang -Wl,-dead_strip -o "$WORK/capi_host" "$WORK/host.o" "$WORK/bridge.o" "$RUNTIME"
rm -f "$ROOT/build/capi_bridge_link.elisa"
"$WORK/capi_host"
