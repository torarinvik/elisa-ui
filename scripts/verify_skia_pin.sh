#!/usr/bin/env bash
# Verify the exact clean Skia source checkout required by renderer fixtures.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
LOCK="$ROOT/third_party/skia.lock"

[[ -f "$LOCK" ]] || { echo "skia pin: missing lockfile $LOCK" >&2; exit 2; }
[[ -d "$SKIA_ROOT" ]] && git -C "$SKIA_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "skia pin: not a git checkout: $SKIA_ROOT" >&2
  exit 2
}
[[ -f "$SKIA_ROOT/include/core/SkCanvas.h" ]] || {
  echo "skia pin: checkout has no include/core/SkCanvas.h: $SKIA_ROOT" >&2
  exit 2
}
if ! git -C "$SKIA_ROOT" diff --quiet || ! git -C "$SKIA_ROOT" diff --cached --quiet ||
   [[ -n "$(git -C "$SKIA_ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "skia pin: refusing a dirty checkout: $SKIA_ROOT" >&2
  exit 2
fi
expected_revision="$(awk -F= '$1 == "revision" { print $2; exit }' "$LOCK")"
actual_revision="$(git -C "$SKIA_ROOT" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$expected_revision" || -z "$actual_revision" || "$actual_revision" != "$expected_revision" ]]; then
  echo "skia pin: expected $expected_revision (found ${actual_revision:-unknown})" >&2
  exit 2
fi
echo "skia pin: $actual_revision"
