#!/usr/bin/env bash
# Fetch and build the exact CPU-raster Skia dependency used by the required
# headless renderer checks. This script never launches an application window.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/third_party/skia.lock"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the checkout location}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"

[[ -f "$LOCK" ]] || { echo "skia build: missing lockfile $LOCK" >&2; exit 2; }
repository="$(awk -F= '$1 == "repository" { print $2; exit }' "$LOCK")"
ref="$(awk -F= '$1 == "ref" { print $2; exit }' "$LOCK")"
revision="$(awk -F= '$1 == "revision" { print $2; exit }' "$LOCK")"
[[ -n "$repository" && -n "$ref" && -n "$revision" ]] || {
  echo "skia build: lockfile is missing repository/ref/revision" >&2
  exit 2
}

command -v git >/dev/null || { echo "skia build: git is required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "skia build: python3 is required" >&2; exit 2; }
# depot_tools is not needed for this build. Skia fetches its own gn, and a
# plain ninja builds it; prefer depot_tools when it is on PATH, because a
# machine that has it usually wants it used.
NINJA="$(command -v autoninja || command -v ninja || true)"
[[ -n "$NINJA" ]] || {
  echo "skia build: ninja is required (brew install ninja, or use depot_tools)" >&2
  exit 2
}

if [[ ! -d "$SKIA_ROOT" ]]; then
  mkdir -p "$(dirname -- "$SKIA_ROOT")"
  git clone --no-checkout "$repository" "$SKIA_ROOT"
elif ! git -C "$SKIA_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "skia build: existing SKIA_ROOT is not a git checkout: $SKIA_ROOT" >&2
  exit 2
fi

if ! git -C "$SKIA_ROOT" diff --quiet || ! git -C "$SKIA_ROOT" diff --cached --quiet ||
   [[ -n "$(git -C "$SKIA_ROOT" status --porcelain --untracked-files=all)" ]]; then
  echo "skia build: refusing to change a dirty checkout: $SKIA_ROOT" >&2
  exit 2
fi
git -C "$SKIA_ROOT" fetch --tags origin "$revision"
git -C "$SKIA_ROOT" checkout --detach "$revision"
git -C "$SKIA_ROOT" submodule update --init --recursive
python3 "$SKIA_ROOT/tools/git-sync-deps"

# Skia's own gn, unless depot_tools already supplies one.
GN="$(command -v gn || true)"
if [[ -z "$GN" ]]; then
  [[ -x "$SKIA_ROOT/bin/gn" ]] || python3 "$SKIA_ROOT/bin/fetch-gn"
  GN="$SKIA_ROOT/bin/gn"
fi
[[ -x "$GN" ]] || { echo "skia build: no usable gn" >&2; exit 2; }

# Keep the fetch/build path and standalone renderer gates on the same source
# contract. A linked worktree has a `.git` file, not a directory, and is valid
# when Git reports a clean checkout at the pinned revision.
SKIA_ROOT="$SKIA_ROOT" bash "$ROOT/scripts/verify_skia_pin.sh"

gn_args=(
  'target_os="mac"'
  'target_cpu="arm64"'
  'is_official_build=true'
  'is_component_build=false'
  'skia_enable_tools=false'
  'skia_use_gl=false'
  'skia_use_metal=false'
  'skia_use_icu=false'
  'skia_use_harfbuzz=false'
  'skia_use_system_libpng=false'
  'skia_use_libpng_encode=true'
  'skia_use_libpng_decode=false'
  'skia_use_libjpeg_turbo_decode=false'
  'skia_use_libjpeg_turbo_encode=false'
  'skia_use_jpeg_gainmaps=false'
  'skia_use_libwebp_encode=false'
  'skia_use_libwebp_decode=false'
  'skia_use_libavif=false'
)
mkdir -p "$(dirname -- "$SKIA_OUT")"
joined_args="${gn_args[*]}"
# fetch-gn writes into the checkout, so re-verify the pin after it and before
# anything is built from the tree.
SKIA_ROOT="$SKIA_ROOT" bash "$ROOT/scripts/verify_skia_pin.sh" >/dev/null
# gn locates the source tree by walking up for a .gn file, and this script
# does not run from inside the checkout.
"$GN" gen "$SKIA_OUT" --root="$SKIA_ROOT" --args="$joined_args"
"$NINJA" -C "$SKIA_OUT" skia

actual_revision="$(git -C "$SKIA_ROOT" rev-parse HEAD)"
[[ "$actual_revision" == "$revision" ]] || {
  echo "skia build: checkout moved during build (expected $revision, found $actual_revision)" >&2
  exit 2
}
[[ -f "$SKIA_OUT/libskia.a" ]] || {
  echo "skia build: build completed without $SKIA_OUT/libskia.a" >&2
  exit 2
}
manifest="$SKIA_OUT/elisa-ui-skia-build.lock"
{
  printf 'revision=%s\n' "$actual_revision"
  printf 'lock_sha256=%s\n' "$(shasum -a 256 "$LOCK" | awk '{print $1}')"
  printf 'libskia_sha256=%s\n' "$(shasum -a 256 "$SKIA_OUT/libskia.a" | awk '{print $1}')"
} > "$manifest"
SKIA_ROOT="$SKIA_ROOT" SKIA_OUT="$SKIA_OUT" bash "$ROOT/scripts/verify_skia_build.sh"
echo "skia build: $actual_revision -> $SKIA_OUT/libskia.a (provenance=$manifest)"
