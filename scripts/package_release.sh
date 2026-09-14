#!/usr/bin/env bash
# Package a versioned elisa-ui release for the SDK.
#
# The bundle is source plus docs plus examples, with a license, a resolved
# toolchain revision, and a SHA-256 integrity manifest. The SDK consumes this
# layout; nothing here builds native objects, so the package is reproducible on
# any host that has this checkout.
#
# Usage: scripts/package_release.sh [output-dir]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"

VERSION_MAJOR="$(grep -oE 'VERSION_MAJOR: u32 = [0-9]+' "$ROOT/src/core/ui_build.elisa" | grep -oE '[0-9]+$')"
VERSION_MINOR="$(grep -oE 'VERSION_MINOR: u32 = [0-9]+' "$ROOT/src/core/ui_build.elisa" | grep -oE '[0-9]+$')"
VERSION_PATCH="$(grep -oE 'VERSION_PATCH: u32 = [0-9]+' "$ROOT/src/core/ui_build.elisa" | grep -oE '[0-9]+$')"
[[ -n "$VERSION_MAJOR" && -n "$VERSION_MINOR" && -n "$VERSION_PATCH" ]] || { echo "package: could not read the framework version from src/core/ui_build.elisa" >&2; exit 2; }
VERSION="$VERSION_MAJOR.$VERSION_MINOR.$VERSION_PATCH"

REVISION="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
TOOLCHAIN="$(git -C "$STAGE1" rev-parse HEAD 2>/dev/null || echo unknown)"
TOOLCHAIN_PRODUCT="${STAGE1}/bin/elisac-stage1"
TOOLCHAIN_SHA="$(shasum -a 256 "$TOOLCHAIN_PRODUCT" 2>/dev/null | awk '{print $1}' || echo unknown)"
[[ -n "$TOOLCHAIN_SHA" ]] || TOOLCHAIN_SHA="unknown"

OUTPUT_BASE="${1:-$ROOT/build/release}"
BUNDLE="$OUTPUT_BASE/elisa-ui-$VERSION"
mkdir -p "$OUTPUT_BASE"
STAGING="$(mktemp -d "$OUTPUT_BASE/.elisa-ui-$VERSION.stage.XXXXXX")"
BACKUP=""

cleanup_package_dirs() {
  local exit_status=$?
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf -- "$STAGING" || echo "package: could not remove temporary staging directory $STAGING" >&2
  fi
  if [[ -n "$BACKUP" && ( -e "$BACKUP" || -L "$BACKUP" ) ]]; then
    if [[ ! -e "$BUNDLE" && ! -L "$BUNDLE" ]]; then
      mv -- "$BACKUP" "$BUNDLE" || echo "package: previous bundle is preserved at $BACKUP" >&2
    else
      rm -rf -- "$BACKUP" || echo "package: previous bundle remains at $BACKUP" >&2
    fi
  fi
  return "$exit_status"
}

trap cleanup_package_dirs EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Source, headers, docs and examples are the payload. Build output and caches
# are deliberately excluded so the bundle is a source release.
cp -R "$ROOT/src" "$ROOT/include" "$ROOT/docs" "$ROOT/examples" "$ROOT/scripts" "$STAGING/"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/third_party/skia.lock" "$STAGING/"

cat > "$STAGING/release.json" <<EOF
{
  "name": "elisa-ui",
  "version": "$VERSION",
  "license": "MIT",
  "revision": "$REVISION",
  "toolchain": {
    "revision": "$TOOLCHAIN",
    "product_sha256": "$TOOLCHAIN_SHA"
  }
}
EOF

# Integrity manifest over every bundled file except the manifest itself.
(
  cd "$STAGING"
  find . -type f ! -name 'files.sha256' -print | LC_ALL=C sort | xargs shasum -a 256 > files.sha256
)
FILE_COUNT="$(wc -l < "$STAGING/files.sha256" | tr -d ' ')"
BUNDLE_DIGEST="$(shasum -a 256 "$STAGING/files.sha256" | awk '{print $1}')"

# Stage and hash everything before moving the previous release. Keep the old
# bundle recoverable until the completed directory has taken its final name.
BACKUP="$(mktemp -d "$OUTPUT_BASE/.elisa-ui-$VERSION.backup.XXXXXX")"
rmdir "$BACKUP"
if [[ -e "$BUNDLE" || -L "$BUNDLE" ]]; then
  mv -- "$BUNDLE" "$BACKUP"
fi
if ! mv -- "$STAGING" "$BUNDLE"; then
  echo "package: could not install the completed bundle at $BUNDLE" >&2
  if [[ -e "$BACKUP" || -L "$BACKUP" ]]; then
    if mv -- "$BACKUP" "$BUNDLE"; then
      BACKUP=""
    fi
  fi
  exit 1
fi
if [[ -e "$BACKUP" || -L "$BACKUP" ]]; then
  rm -rf -- "$BACKUP"
fi
BACKUP=""

echo "package: elisa-ui $VERSION -> $BUNDLE"
echo "package: files=$FILE_COUNT revision=$REVISION"
echo "package: manifest_sha256=$BUNDLE_DIGEST"
