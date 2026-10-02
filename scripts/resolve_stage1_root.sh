#!/usr/bin/env bash
# Select the compiler root used by elisa-ui scripts.
# Precedence preserves explicit/development workflows and lets a clean install
# use the immutable snapshot produced by Elisa's install_stage1.sh.
set -euo pipefail

ROOT_INPUT="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(cd -- "$ROOT_INPUT" && pwd)"

valid_root() {
  local candidate="$1"
  [[ -x "$candidate/bin/elisac-stage1" && \
     -f "$candidate/build/runtime/elisacore_runtime.o" && \
     -x "$candidate/scripts/elisac_stage1.sh" ]]
}

if [[ -n "${ELISA_UI_STAGE1:-}" ]]; then
  if ! valid_root "$ELISA_UI_STAGE1"; then
    echo "toolchain: selected ELISA_UI_STAGE1 is incomplete: $ELISA_UI_STAGE1" >&2
    exit 2
  fi
  (cd -- "$ELISA_UI_STAGE1" && pwd)
  exit 0
fi

# Keep the established adjacent development checkout first when it exists.
DEVELOPMENT_ROOT="$ROOT/../Elisa-compiler"
if valid_root "$DEVELOPMENT_ROOT"; then
  (cd -- "$DEVELOPMENT_ROOT" && pwd)
  exit 0
fi

# Elisa's installer snapshots the complete compiler root at this stable path;
# ELISAC_PREFIX lets package managers and users relocate that install.
ELISA_PREFIX="${ELISAC_PREFIX:-${HOME}/.elisac}"
INSTALLED_ROOT="$ELISA_PREFIX/stage1"
if [[ -f "$INSTALLED_ROOT/SNAPSHOT" ]] && valid_root "$INSTALLED_ROOT"; then
  (cd -- "$INSTALLED_ROOT" && pwd)
  exit 0
fi

echo "toolchain: no compiler checkout or installed Stage1 snapshot was found" >&2
echo "install Stage1 with the Elisa compiler, or set ELISA_UI_STAGE1 to its compiler root" >&2
exit 2
