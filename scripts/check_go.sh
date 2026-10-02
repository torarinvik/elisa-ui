#!/usr/bin/env bash
# Build and run the optional Go host example against the real Elisa C ABI.
#
# The Go package is intentionally a thin cgo face over include/elisa_ui.h. The
# bridge is compiled from the current Elisa sources and linked into the example
# so this check proves the binding against the actual framework, not a C stub.
# It is a host-driven, single-UI-thread example and never opens a window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"

command -v go >/dev/null 2>&1 || { echo "go: skipped (no Go toolchain)"; exit 0; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME" >&2; exit 2; }

# Keep linker object paths free of spaces: cgo tokenizes CGO_LDFLAGS before
# handing it to the external linker, while this repository commonly lives in a
# path containing spaces.
WORK="$(mktemp -d /tmp/elisa-ui-go-check.XXXXXX)"
mkdir -p "$ROOT/build"
SOURCE_DIR="$(mktemp -d "$ROOT/build/go-check-source.XXXXXX")"
trap 'rm -rf "$WORK" "$SOURCE_DIR"' EXIT INT TERM HUP

# The two Elisa C adapters supply the host functions and the application
# callback contract. Keep this source temporary so parallel checks do not share
# a mutable bridge file.
cat > "$SOURCE_DIR/bridge.elisa" <<'EOF'
include "../../src/capi/ui_capi.elisa"
include "../../src/capi/ui_capi_app.elisa"
EOF
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/bridge.o" "$SOURCE_DIR/bridge.elisa"
cp "$RUNTIME" "$WORK/runtime.o"
# Archives are important here: cgo repeats its linker flags for each generated
# cgo package, while archive members are extracted only once. Passing raw
# objects would therefore produce duplicate Elisa symbols.
ar rcs "$WORK/libelisa_bridge.a" "$WORK/bridge.o"
ar rcs "$WORK/libelisa_runtime.a" "$WORK/runtime.o"

# The package's pure text-prefix tests still compile its C ABI call wrappers.
# Link this no-op callback table for that unit-test binary; the real integration
# host below exports the actual callbacks from Go instead.
clang -std=c11 -Wall -Wextra -Werror -I"$ROOT/include" \
  -c -o "$WORK/test_callbacks.o" "$ROOT/test/go_capi_test_stubs.c"
ar rcs "$WORK/libelisa_test_callbacks.a" "$WORK/test_callbacks.o"

CGO_ENABLED=1 CGO_LDFLAGS="$WORK/libelisa_bridge.a $WORK/libelisa_runtime.a $WORK/libelisa_test_callbacks.a -Wl,-dead_strip -Wl,-no_warn_duplicate_libraries" \
  go test ./bindings/go/elisa_ui

# cgo passes these objects to the external linker. They are absolute paths so
# the package remains usable from any working directory while the check still
# binds the freshly compiled Elisa implementation.
CGO_ENABLED=1 CGO_LDFLAGS="$WORK/libelisa_bridge.a $WORK/libelisa_runtime.a -Wl,-dead_strip -Wl,-no_warn_duplicate_libraries" \
  go build -o "$WORK/go_host" "$ROOT/examples/go"
"$WORK/go_host"
