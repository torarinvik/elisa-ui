#!/usr/bin/env bash
# Build an iOS application from an example's UIKit entry point.
#
# Everything is cross-compiled: the Elisa sources, the runtime object and the
# Objective-C shim all target the requested iOS triple. The link goes through
# the compiler's own `-emit exe` path with ELISA_CLANG pointed at a wrapper
# that adds the SDK, the triple and the frameworks -- that way the weak
# callback fallbacks the runtime expects come from the compiler that defines
# them rather than from a copy in this repository that would drift.
#
# Usage: build_uikit.sh [example] [simulator|device]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
EXAMPLE="${1:-hello}"
FLAVOR="${2:-simulator}"
ENTRY="$ROOT/examples/$EXAMPLE/uikit_main.elisa"
DEPLOYMENT="${ELISA_UI_IOS_DEPLOYMENT:-17.0}"

[[ "$(uname -s)" == "Darwin" ]] || { echo "the UIKit backend is macOS-hosted" >&2; exit 2; }
[[ -f "$ENTRY" ]] || { echo "no UIKit entry: examples/$EXAMPLE/uikit_main.elisa" >&2; exit 2; }
[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }

case "$FLAVOR" in
  simulator)
    SDK_NAME=iphonesimulator
    TRIPLE="$(uname -m)-apple-ios${DEPLOYMENT}-simulator"
    PLATFORM_NAME=iPhoneSimulator
    ;;
  device)
    SDK_NAME=iphoneos
    TRIPLE="arm64-apple-ios${DEPLOYMENT}"
    PLATFORM_NAME=iPhoneOS
    ;;
  *)
    echo "unknown flavor '$FLAVOR' (expected simulator or device)" >&2
    exit 2
    ;;
esac
SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"

OUT="$ROOT/build/ios/$FLAVOR"
mkdir -p "$OUT"

# The iOS runtime object. The host one is Mach-O for macOS and cannot be
# linked into an iOS image, so build the same runtime source for this triple.
RUNTIME="$OUT/elisacore_runtime.o"
"$STAGE1/bin/elisac-stage1" -emit obj -O0 -target-triple "$TRIPLE" \
  -o "$OUT/runtime_core.o" "$STAGE1/elisacore_std/native_runtime_support.elisa"
bash "$STAGE1/scripts/write_profiler_hook_fallbacks.sh" > "$OUT/profiler_hooks.c"
xcrun --sdk "$SDK_NAME" clang -target "$TRIPLE" -isysroot "$SDK" \
  -c -o "$OUT/profiler_hooks.o" "$OUT/profiler_hooks.c"
xcrun --sdk "$SDK_NAME" clang -target "$TRIPLE" -isysroot "$SDK" \
  -r -o "$RUNTIME" "$OUT/runtime_core.o" "$OUT/profiler_hooks.o"

# The Objective-C shim, one translation unit.
xcrun --sdk "$SDK_NAME" clang -target "$TRIPLE" -isysroot "$SDK" -fobjc-arc \
  -c -Wall -Wextra -Werror -o "$OUT/uikit_shim.o" "$ROOT/src/platform/uikit/uikit_shim.m"

# The link driver the compiler will invoke. It receives the compiler's own
# link line and adds only what is specific to this platform.
LINKER="$OUT/ios_clang.sh"
cat > "$LINKER" <<LINK
#!/usr/bin/env bash
set -euo pipefail
exec xcrun --sdk "$SDK_NAME" clang -target "$TRIPLE" -isysroot "$SDK" "\$@" \\
  "$OUT/uikit_shim.o" \\
  -framework UIKit -framework Foundation -framework CoreGraphics \\
  -framework CoreText -framework ImageIO
LINK
chmod +x "$LINKER"

BINARY="$OUT/${EXAMPLE}_uikit"
ELISA_CLANG="$LINKER" ELISA_RUNTIME_OBJ="$RUNTIME" \
  "$STAGE1/bin/elisac-stage1" -emit exe -O0 -target-triple "$TRIPLE" \
  -o "$BINARY" "$ENTRY"

# Package it as a real .app so it can be installed on a simulator or signed
# for a device. The bundle metadata is application identity, so it is stated
# here rather than inferred by the shim.
APP="$OUT/${EXAMPLE}_uikit.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$BINARY" "$APP/${EXAMPLE}_uikit"
PLIST="$APP/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleExecutable -string "${EXAMPLE}_uikit" "$PLIST"
plutil -insert CFBundleIdentifier -string "org.elisa-ui.${EXAMPLE}.uikit" "$PLIST"
plutil -insert CFBundleName -string "elisa-ui" "$PLIST"
plutil -insert CFBundleDisplayName -string "elisa-ui" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "0.1.0" "$PLIST"
plutil -insert CFBundleVersion -string "1" "$PLIST"
plutil -insert MinimumOSVersion -string "$DEPLOYMENT" "$PLIST"
plutil -insert CFBundleSupportedPlatforms -json "[\"$PLATFORM_NAME\"]" "$PLIST"
plutil -insert UILaunchScreen -json '{}' "$PLIST"
plutil -insert UIRequiredDeviceCapabilities -json '["arm64"]' "$PLIST"
plutil -insert UISupportedInterfaceOrientations -json \
  '["UIInterfaceOrientationPortrait","UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight"]' "$PLIST"
codesign --force --sign - "$APP" >/dev/null

echo "built $BINARY"
echo "built $APP"
