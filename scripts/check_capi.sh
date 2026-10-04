#!/usr/bin/env bash
# Build a real C program against the library and run it.
#
# The header and the Elisa side are two hand-written descriptions of one ABI, and
# nothing else checks that they agree: the elisa suite never sees the header, and
# the header never sees the Elisa types. This links them and asserts a struct
# whose layout C computed reaches an Elisa function with its fields intact.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="$(bash "$ROOT/scripts/resolve_stage1_root.sh" "$ROOT")"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }

# The header and the Elisa source are two hand-written descriptions of one ABI.
# Before building, assert they describe the same set of functions in both
# directions: host-facing functions Elisa defines and the header declares, and
# app-facing callbacks the header declares and Elisa declares as externs. This
# catches a symbol added to one side and forgotten on the other.
header_host="$(grep -oE 'elisa_ui_[a-z_]+\(' "$ROOT/include/elisa_ui.h" | sed 's/($//' | grep -v '^elisa_ui_on_' | sort -u)"
elisa_host="$(grep -ohE '^def elisa_ui_[a-z_]+\(' "$ROOT"/src/capi/*.elisa | sed 's/^def //; s/($//' | grep -v '^elisa_ui_on_' | sort -u)"
header_app="$(grep -oE 'elisa_ui_on_[a-z_]+\(' "$ROOT/include/elisa_ui.h" | sed 's/($//' | sort -u)"
elisa_app="$(grep -ohE '^extern elisa_ui_on_[a-z_]+\(' "$ROOT"/src/capi/ui_capi_app.elisa | sed 's/^extern //; s/($//' | sort -u)"

if ! diff <(printf '%s\n' "$header_host") <(printf '%s\n' "$elisa_host") >/dev/null; then
  echo "capi: host-facing symbols differ between include/elisa_ui.h and src/capi/ui_capi.elisa" >&2
  diff <(printf '%s\n' "$header_host") <(printf '%s\n' "$elisa_host") >&2 || true
  exit 1
fi
if ! diff <(printf '%s\n' "$header_app") <(printf '%s\n' "$elisa_app") >/dev/null; then
  echo "capi: app-facing callbacks differ between include/elisa_ui.h and src/capi/ui_capi_app.elisa" >&2
  diff <(printf '%s\n' "$header_app") <(printf '%s\n' "$elisa_app") >&2 || true
  exit 1
fi

mkdir -p "$ROOT/build"
WORK="$(mktemp -d "$ROOT/build/capi-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# The Elisa side: both adapters at once, which also proves they can coexist.
cat > "$WORK/bridge.elisa" <<'EOF'
include "../../src/capi/ui_capi.elisa"
include "../../src/capi/ui_capi_app.elisa"
include "../../test/capi_backend_stubs.elisa"
EOF
# Keep the generated source beside its temporary outputs. The relative include
# starts at build/capi-check.XXXXXX/bridge.elisa and reaches this repository's
# src directory without occupying a fixed, potentially user-owned path.
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$WORK/bridge.o" "$WORK/bridge.elisa"

# Source declarations can agree while code generation silently changes the
# names that the linker sees. Audit the generated object too: the C-host API
# must be defined by the bridge, while the C-app callbacks must remain imports
# supplied by the embedding application. Apple nm prints the Mach-O leading
# underscore; remove exactly that decoration before comparing public names.
object_host="$(nm -gUj "$WORK/bridge.o" | sed 's/^_//' | grep -E '^elisa_ui_[a-z_]+$' | grep -v '^elisa_ui_on_' | sort -u)"
object_app="$(nm -guj "$WORK/bridge.o" | sed 's/^_//' | grep -E '^elisa_ui_on_[a-z_]+$' | sort -u)"
if ! diff <(printf '%s\n' "$header_host") <(printf '%s\n' "$object_host") >/dev/null; then
  echo "capi: generated host-facing symbols differ from include/elisa_ui.h" >&2
  diff <(printf '%s\n' "$header_host") <(printf '%s\n' "$object_host") >&2 || true
  exit 1
fi
if ! diff <(printf '%s\n' "$header_app") <(printf '%s\n' "$object_app") >/dev/null; then
  echo "capi: generated callback imports differ from include/elisa_ui.h" >&2
  diff <(printf '%s\n' "$header_app") <(printf '%s\n' "$object_app") >&2 || true
  exit 1
fi

ar rcs "$WORK/libelisa_ui_capi.a" "$WORK/bridge.o"
clang -dynamiclib -Wl,-undefined,dynamic_lookup \
  -o "$WORK/libelisa_ui_capi.dylib" "$WORK/bridge.o" "$RUNTIME"
shared_host="$(nm -gUj "$WORK/libelisa_ui_capi.dylib" | sed 's/^_//' | grep -E '^elisa_ui_[a-z_]+$' | grep -v '^elisa_ui_on_' | sort -u)"
shared_app="$(nm -guj "$WORK/libelisa_ui_capi.dylib" | sed 's/^_//' | grep -E '^elisa_ui_on_[a-z_]+$' | sort -u)"
if ! diff <(printf '%s\n' "$header_host") <(printf '%s\n' "$shared_host") >/dev/null; then
  echo "capi: shared-library host exports differ from include/elisa_ui.h" >&2
  diff <(printf '%s\n' "$header_host") <(printf '%s\n' "$shared_host") >&2 || true
  exit 1
fi
if ! diff <(printf '%s\n' "$header_app") <(printf '%s\n' "$shared_app") >/dev/null; then
  echo "capi: shared-library callback imports differ from include/elisa_ui.h" >&2
  diff <(printf '%s\n' "$header_app") <(printf '%s\n' "$shared_app") >&2 || true
  exit 1
fi

clang -std=c11 -Wall -Wextra -I"$ROOT/include" \
  -c -o "$WORK/host.o" "$ROOT/examples/capi/c_host.c"
clang++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT/include" \
  -c -o "$WORK/header_cpp.o" "$ROOT/examples/capi/cpp_header_check.cc"
clang -Wl,-dead_strip -o "$WORK/capi_host" "$WORK/host.o" "$WORK/libelisa_ui_capi.a" "$RUNTIME"
"$WORK/capi_host"
clang -Wl,-dead_strip -Wl,-export_dynamic -o "$WORK/capi_host_shared" \
  "$WORK/host.o" "$WORK/libelisa_ui_capi.dylib"
DYLD_LIBRARY_PATH="$WORK${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$WORK/capi_host_shared"
