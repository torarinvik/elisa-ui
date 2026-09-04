#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../elisa-ui-worktrees/stage1}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
EXAMPLE="${1:-hello}"
ENTRY="$ROOT/examples/$EXAMPLE/appkit_canvas_main.elisa"

[[ "$(uname -s)" == "Darwin" ]] || { echo "the AppKit canvas backend is macOS only" >&2; exit 2; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1 (run scripts/elisac_stage1.sh --seed there)" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME (run scripts/build_runtime_object.sh there)" >&2; exit 2; }
[[ -f "$ENTRY" ]] || { echo "no AppKit canvas entry: examples/$EXAMPLE/appkit_canvas_main.elisa" >&2; exit 2; }
mkdir -p "$ROOT/build"
clang -c -fobjc-arc -Wall -Wextra -Werror -o "$ROOT/build/appkit_canvas_shim.o" "$ROOT/src/platform/appkit/appkit_canvas_shim.m"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/${EXAMPLE}_appkit_canvas.o" "$ENTRY"
clang -Wl,-dead_strip -o "$ROOT/build/${EXAMPLE}_appkit_canvas" \
  "$ROOT/build/${EXAMPLE}_appkit_canvas.o" "$ROOT/build/appkit_canvas_shim.o" "$RUNTIME" -framework Cocoa

# Package the same binary as a real macOS application. Keeping the raw binary
# above is useful to tests and debuggers; the bundle supplies Finder/Dock identity,
# Retina declaration and the standard application lifecycle metadata.
APP="$ROOT/build/${EXAMPLE}_appkit_canvas.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
mkdir -p "$MACOS"
cp "$ROOT/build/${EXAMPLE}_appkit_canvas" "$MACOS/${EXAMPLE}_appkit_canvas"
PLIST="$CONTENTS/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleExecutable -string "${EXAMPLE}_appkit_canvas" "$PLIST"
plutil -insert CFBundleIdentifier -string "org.elisa-ui.${EXAMPLE}.canvas" "$PLIST"
plutil -insert CFBundleName -string "elisa-ui" "$PLIST"
plutil -insert CFBundleDisplayName -string "elisa-ui Canvas" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "0.1.0" "$PLIST"
plutil -insert CFBundleVersion -string "1" "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
plutil -insert NSPrincipalClass -string "NSApplication" "$PLIST"
codesign --force --sign - "$APP" >/dev/null

echo "built $ROOT/build/${EXAMPLE}_appkit_canvas"
echo "built $APP"
