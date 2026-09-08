#!/usr/bin/env bash
# Verify that a Skia archive was produced from this checkout and lockfile.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
SKIA_LIB="${SKIA_LIB:-$SKIA_OUT/libskia.a}"
LOCK="$ROOT/third_party/skia.lock"
MANIFEST="$SKIA_OUT/elisa-ui-skia-build.lock"
LIB="$SKIA_LIB"

SKIA_ROOT="$SKIA_ROOT" bash "$ROOT/scripts/verify_skia_pin.sh" >/dev/null
[[ -f "$LIB" ]] || { echo "skia build: no archive at $LIB" >&2; exit 2; }
[[ -f "$MANIFEST" ]] || {
  echo "skia build: missing provenance manifest $MANIFEST" >&2
  echo "skia build: rebuild with scripts/build_skia.sh" >&2
  exit 2
}

manifest_value() {
  local key="$1"
  awk -F= -v wanted="$key" '$1 == wanted { print $2; exit }' "$MANIFEST"
}

expected_revision="$(awk -F= '$1 == "revision" { print $2; exit }' "$LOCK")"
expected_lock_sha256="$(shasum -a 256 "$LOCK" | awk '{print $1}')"
actual_revision="$(git -C "$SKIA_ROOT" rev-parse HEAD)"
actual_lib_sha256="$(shasum -a 256 "$LIB" | awk '{print $1}')"

[[ "$(manifest_value revision)" == "$expected_revision" && "$actual_revision" == "$expected_revision" ]] || {
  echo "skia build: archive provenance revision mismatch" >&2
  exit 2
}
[[ "$(manifest_value lock_sha256)" == "$expected_lock_sha256" ]] || {
  echo "skia build: archive was built from a different lockfile" >&2
  exit 2
}
[[ "$(manifest_value libskia_sha256)" == "$actual_lib_sha256" ]] || {
  echo "skia build: archive hash does not match provenance manifest" >&2
  exit 2
}
echo "skia build: provenance verified revision=$actual_revision libskia_sha256=$actual_lib_sha256"
