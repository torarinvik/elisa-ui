#!/usr/bin/env bash
# Exercise the same compiler-root selection used by every shell build entrypoint.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-toolchain.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT INT TERM HUP

make_root() {
  local compiler_root="$1"
  local snapshot="${2:-0}"
  mkdir -p \
    "$compiler_root/bin" \
    "$compiler_root/build/runtime" \
    "$compiler_root/scripts" \
    "$compiler_root/src" \
    "$compiler_root/elisacore_std"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$compiler_root/bin/elisac-stage1"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$compiler_root/scripts/elisac_stage1.sh"
  printf 'runtime fixture\n' >"$compiler_root/build/runtime/elisacore_runtime.o"
  printf 'source fixture\n' >"$compiler_root/src/compiler.elisa"
  printf 'runtime source fixture\n' >"$compiler_root/elisacore_std/runtime.elisa"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$compiler_root/scripts/build_runtime_object.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$compiler_root/scripts/write_profiler_hook_fallbacks.sh"
  chmod +x "$compiler_root/bin/elisac-stage1" "$compiler_root/scripts/elisac_stage1.sh"
  if [[ "$snapshot" == 1 ]]; then
    printf 'revision: test-revision\ntaken: 2026-09-30T00:00:00Z\nfrom: test-fixture\n' >"$compiler_root/SNAPSHOT"
  fi
  touch \
    "$compiler_root/build/runtime/elisacore_runtime.o" \
    "$compiler_root/bin/elisac-stage1"
}

project="$WORK/project/ui"
mkdir -p "$project"
sibling="$WORK/project/Elisa-compiler"
installed_prefix="$WORK/user install"
installed="$installed_prefix/stage1"
explicit="$WORK/explicit compiler"
make_root "$sibling"
make_root "$installed" 1
make_root "$explicit"

selected="$(ELISA_UI_STAGE1="$explicit" ELISAC_PREFIX="$installed_prefix" bash "$ROOT/scripts/resolve_stage1_root.sh" "$project")"
expected="$(cd -- "$explicit" && pwd)"
[[ "$selected" == "$expected" ]] || { echo "toolchain resolver ignored ELISA_UI_STAGE1 (selected=$selected expected=$expected)" >&2; exit 1; }

selected="$(env -u ELISA_UI_STAGE1 ELISAC_PREFIX="$installed_prefix" bash "$ROOT/scripts/resolve_stage1_root.sh" "$project")"
expected="$(cd -- "$sibling" && pwd)"
[[ "$selected" == "$expected" ]] || { echo "toolchain resolver did not preserve the development checkout" >&2; exit 1; }

clean_project="$WORK/clean install/ui"
mkdir -p "$clean_project"
selected="$(env -u ELISA_UI_STAGE1 ELISAC_PREFIX="$installed_prefix" bash "$ROOT/scripts/resolve_stage1_root.sh" "$clean_project")"
expected="$(cd -- "$installed" && pwd)"
[[ "$selected" == "$expected" ]] || { echo "toolchain resolver did not select the installed snapshot" >&2; exit 1; }

if ! toolchain_output="$(env -u ELISA_ALLOW_UNVERIFIED_STAGE1 \
  ELISA_UI_STAGE1="$installed" \
  ELISA_UI_REQUIRE_CURRENT_STAGE1=1 \
  bash "$ROOT/scripts/check_toolchain.sh" 2>&1)"; then
  printf '%s\n' "$toolchain_output" >&2
  echo "toolchain check rejected a fresh installed snapshot" >&2
  exit 1
fi
[[ "$toolchain_output" == *"stage1 snapshot revision=test-revision"* ]] || {
  echo "toolchain check omitted installed snapshot provenance" >&2
  exit 1
}
[[ "$toolchain_output" == *"snapshot has no Git ancestry"* ]] || {
  echo "toolchain check omitted the snapshot ancestry limitation" >&2
  exit 1
}

missing_project="$WORK/missing/ui"
mkdir -p "$missing_project"
if env -u ELISA_UI_STAGE1 ELISAC_PREFIX="$WORK/no install" \
  bash "$ROOT/scripts/resolve_stage1_root.sh" "$missing_project" >/dev/null 2>&1; then
  echo "toolchain resolver accepted a missing compiler" >&2
  exit 1
fi

echo "toolchain resolution: explicit, development, and installed-snapshot selection passed"
