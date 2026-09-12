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
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"

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
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE"

# Source, headers, docs and examples are the payload. Build output and caches
# are deliberately excluded so the bundle is a source release.
cp -R "$ROOT/src" "$ROOT/include" "$ROOT/docs" "$ROOT/examples" "$ROOT/scripts" "$BUNDLE/"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/third_party/skia.lock" "$BUNDLE/"

cat > "$BUNDLE/release.json" <<EOF
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
  cd "$BUNDLE"
  find . -type f ! -name 'files.sha256' -print | LC_ALL=C sort | xargs shasum -a 256 > files.sha256
)
FILE_COUNT="$(wc -l < "$BUNDLE/files.sha256" | tr -d ' ')"
BUNDLE_DIGEST="$(shasum -a 256 "$BUNDLE/files.sha256" | awk '{print $1}')"

echo "package: elisa-ui $VERSION -> $BUNDLE"
echo "package: files=$FILE_COUNT revision=$REVISION"
echo "package: manifest_sha256=$BUNDLE_DIGEST"
