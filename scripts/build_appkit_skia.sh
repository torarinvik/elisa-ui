#!/usr/bin/env bash
# Build the optional AppKit custom-canvas product with Skia presentation.
# This never launches the product; use check_appkit_skia.sh for the headless
# compositor fixture.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
SKIA_ROOT="${SKIA_ROOT:?set SKIA_ROOT to the pinned checkout from third_party/skia.lock}"
SKIA_OUT="${SKIA_OUT:-$SKIA_ROOT/out/elisa}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
EXAMPLE="${1:-hello}"
ENTRY="$ROOT/examples/$EXAMPLE/appkit_skia_canvas_main.elisa"

[[ "$(uname -s)" == "Darwin" ]] || { echo "the AppKit Skia backend is macOS only" >&2; exit 2; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME" >&2; exit 2; }
[[ -f "$ENTRY" ]] || { echo "no AppKit Skia entry: $ENTRY" >&2; exit 2; }
[[ -f "$SKIA_OUT/libskia.a" ]] || { echo "no Skia archive at $SKIA_OUT/libskia.a" >&2; exit 2; }
bash "$ROOT/scripts/check_toolchain.sh"

mkdir -p "$ROOT/build"
clang -c -fobjc-arc -Wall -Wextra -Werror -DELISA_UI_USE_SKIA -o "$ROOT/build/appkit_canvas_skia_shim.o" \
  "$ROOT/src/platform/appkit/appkit_canvas_shim.m"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/${EXAMPLE}_appkit_skia.o" "$ENTRY"
clang++ -std=c++20 -DSK_BUILD_FOR_MAC -fPIC -I"$ROOT" -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/appkit/appkit_skia_host.cpp" -o "$ROOT/build/appkit_skia_host.o"
clang++ -std=c++17 -fPIC -I"$SKIA_ROOT" -c \
  "$ROOT/src/platform/skia/skia_canvas_shim.cpp" -o "$ROOT/build/skia_canvas_shim.o"

link_inputs=(
  "$ROOT/build/${EXAMPLE}_appkit_skia.o"
  "$ROOT/build/appkit_canvas_skia_shim.o"
  "$ROOT/build/appkit_skia_host.o"
  "$ROOT/build/skia_canvas_shim.o"
  "$RUNTIME"
  "$SKIA_OUT/libskia.a"
)
for extra in "$SKIA_OUT/libpng.a" "$SKIA_OUT/libzlib.a"; do
  [[ -f "$extra" ]] && link_inputs+=("$extra")
done
clang++ -Wl,-dead_strip -o "$ROOT/build/${EXAMPLE}_appkit_skia" "${link_inputs[@]}" \
  -framework Cocoa -framework CoreText -framework CoreGraphics -framework ImageIO -lz

APP="$ROOT/build/${EXAMPLE}_appkit_skia.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
mkdir -p "$MACOS"
cp "$ROOT/build/${EXAMPLE}_appkit_skia" "$MACOS/${EXAMPLE}_appkit_skia"
PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleExecutable -string "${EXAMPLE}_appkit_skia" "$PLIST"
plutil -insert CFBundleIdentifier -string "org.elisa-ui.${EXAMPLE}.skia" "$PLIST"
plutil -insert CFBundleName -string "elisa-ui" "$PLIST"
plutil -insert CFBundleDisplayName -string "elisa-ui Skia Canvas" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "0.1.0" "$PLIST"
plutil -insert CFBundleVersion -string "1" "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
plutil -insert NSPrincipalClass -string "NSApplication" "$PLIST"
codesign --force --sign - "$APP" >/dev/null

echo "built $ROOT/build/${EXAMPLE}_appkit_skia"
echo "built $APP"
