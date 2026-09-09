#!/usr/bin/env bash
# Validate the UIKit backend without a device or a simulator runtime.
#
# Two independent halves, because the backend has two:
#
#   1. The whole product is cross-compiled and linked for the simulator and for
#      a device. That proves the UIKit API use is correct and that the two
#      halves of the backend agree on their shared ABI.
#   2. Everything below the shim is ordinary Apple platform code -- input
#      routing, semantics, surface facts, CoreGraphics/CoreText painting -- so
#      it is built and RUN here against C stand-ins for the shim's entry
#      points, including one real off-screen frame written out as a PNG.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "uikit: skipped (not macOS)"
  exit 0
fi
if ! SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)" || [[ ! -d "$SDK" ]]; then
  echo "uikit: skipped (no iOS SDK installed)"
  exit 0
fi

SHIM="$ROOT/src/platform/uikit/uikit_shim.m"
# The shim is one translation unit spread over an umbrella and the fragments it
# #imports. Every source-level policy check below must read all of them: a
# decision that moved into a fragment would otherwise pass unseen.
SHIM_SOURCES=("$SHIM" "$ROOT"/src/platform/uikit/shim/*.m)

# --- 1. A real iOS build -----------------------------------------------
#
# Cross-compile and link the whole product for the simulator and for a device.
# A successful link is the strongest available proof that the two halves of the
# backend agree: every callback the shim calls must be defined by the Elisa
# object, and every entry point Elisa declared extern must exist in the shim.

for flavor in simulator device; do
  if ! bash "$ROOT/scripts/build_uikit.sh" hello "$flavor" >/dev/null 2>"$ROOT/build/uikit_${flavor}.log"; then
    echo "uikit: the $flavor build failed" >&2
    cat "$ROOT/build/uikit_${flavor}.log" >&2
    exit 1
  fi
done
SIMULATOR_BINARY="$ROOT/build/ios/simulator/hello_uikit"
DEVICE_BINARY="$ROOT/build/ios/device/hello_uikit"
vtool -show-build-version "$SIMULATOR_BINARY" | grep -q 'platform IOSSIMULATOR' ||
  { echo "uikit: the simulator build is not an iOS simulator image" >&2; exit 1; }
vtool -show-build-version "$DEVICE_BINARY" | grep -q 'platform IOS$' ||
  { echo "uikit: the device build is not an iOS device image" >&2; exit 1; }
for framework in UIKit Foundation CoreGraphics CoreText; do
  otool -L "$DEVICE_BINARY" | grep -q "/${framework}.framework/" ||
    { echo "uikit: the device build does not link $framework" >&2; exit 1; }
done
plutil -lint "$ROOT/build/ios/device/hello_uikit.app/Info.plist" >/dev/null
codesign --verify --strict "$ROOT/build/ios/simulator/hello_uikit.app"

# --- 2. Architecture guards --------------------------------------------
# The shim forwards facts and performs operations. Every decision belongs to
# Elisa, so these are "must not contain" checks over the whole unit.

fail() { echo "uikit: $1" >&2; exit 1; }

grep -Eq 'getenv\("ELISA_UI_(SMOKE_FRAMES|SNAPSHOT)"' "${SHIM_SOURCES[@]}" &&
  fail "environment policy leaked back into Objective-C"
grep -Eq '@autoreleasepool' "${SHIM_SOURCES[@]}" &&
  fail "autorelease scope leaked back into Objective-C"
# The semantic child list is built by Elisa as an immutable CFArray. The
# gesture recognizer's allowedTouchTypes is an SDK configuration fact, not a
# framework decision, so the guard names the collection types that would mean
# the shim had started keeping a widget list of its own.
grep -Eq '\bNSMutableArray\b|arrayWithCapacity:|accessibilityElements[[:space:]]*=[[:space:]]*@\[' "${SHIM_SOURCES[@]}" &&
  fail "accessibility child-list construction leaked back into Objective-C"
grep -Eq '\bUIFont\b|\bNSAttributedString\b|CTFontCreate|CTLineDraw' "${SHIM_SOURCES[@]}" &&
  fail "font construction or text rendering leaked back into Objective-C"
grep -Eq 'CGContext(Save|Restore)GState|CGContextFillPath|CGContextAddArc' "${SHIM_SOURCES[@]}" &&
  fail "CoreGraphics rendering leaked back into Objective-C"
grep -Eq 'UIAccessibilityTrait[A-Z]' "${SHIM_SOURCES[@]}" &&
  fail "accessibility trait policy leaked back into Objective-C"
grep -Eq 'UIKeyboardHIDUsage|UIKeyModifierFlag|modifierFlags[[:space:]]*&' "${SHIM_SOURCES[@]}" &&
  fail "key or modifier decoding leaked back into Objective-C"
grep -Eq 'elisa_uikit_touch\([^,]+,[[:space:]]*[0-9]+[[:space:]]*,[[:space:]]*[0-9]' "${SHIM_SOURCES[@]}" &&
  fail "pointer event-kind policy leaked back into Objective-C"
grep -Eq 'accessibility_adjust\([^,]+,[^,]+,[[:space:]]*[+-]?[01][[:space:]]*\)' "${SHIM_SOURCES[@]}" &&
  fail "accessibility direction policy leaked back into Objective-C"
grep -Eq '@"[^"]+"' "${SHIM_SOURCES[@]}" &&
  fail "framework text leaked back into Objective-C"
# A file-scope UIKit object would be a second owner of state Elisa already
# tracks. A function declaration returning one is fine; a variable is not.
grep -Eq 'static (__strong )?(UIWindow|ElisaUiKitView|ElisaUiKitViewController|ElisaUiKitAppDelegate|NSTimer|NSArray)[[:space:]]*\*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=|;)' "${SHIM_SOURCES[@]}" &&
  fail "UIKit object ownership was hidden in Objective-C state"
grep -Eq '\bstrlen\b|\bstrcmp\b' "$ROOT"/src/platform/uikit/ui_uikit_*.elisa &&
  fail "libc string primitives survived in the Elisa backend"

# --- 3. The Elisa backend, built and run on the host -------------------

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME" >&2; exit 2; }
mkdir -p "$ROOT/build"
STUBS="$ROOT/build/uikit_host_stubs.o"
clang -c -Wall -Wextra -Werror -o "$STUBS" "$ROOT/test/uikit_host_stubs.c"
BIN="$ROOT/build/hello_uikit"
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/hello_uikit.o" \
  "$ROOT/examples/hello/uikit_main.elisa"
clang -Wl,-dead_strip -o "$BIN" "$ROOT/build/hello_uikit.o" "$STUBS" "$RUNTIME" \
  -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework ImageIO

# The two halves of the backend are two hand-written descriptions of one ABI,
# and nothing else compares them. Compile the shim for the simulator and
# require that every elisa_uikit_* symbol it calls is defined by the Elisa
# object, and every one it defines is declared there -- a rename or a changed
# signature on either side shows up here rather than at the first device link.
SHIM_OBJECT="$ROOT/build/uikit_shim_simulator.o"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc \
  -c -Wall -Wextra -Werror -o "$SHIM_OBJECT" "$SHIM"
ELISA_OBJECT="$ROOT/build/hello_uikit.o"
missing="$(comm -23 \
  <(nm -gu "$SHIM_OBJECT" | awk '{print $NF}' | grep '^_elisa_uikit_' | sort -u) \
  <(nm -g "$ELISA_OBJECT" | awk '$2 ~ /^[TDBSC]$/ {print $3}' | grep '^_elisa_uikit_' | sort -u))"
if [[ -n "$missing" ]]; then
  echo "uikit: the shim calls Elisa symbols the backend does not export:" >&2
  echo "$missing" >&2
  exit 1
fi
unused="$(comm -13 \
  <(nm -gu "$SHIM_OBJECT" | awk '{print $NF}' | grep '^_elisa_uikit_' | sort -u) \
  <(nm -g "$ELISA_OBJECT" | awk '$2 ~ /^[TDBSC]$/ {print $3}' | grep '^_elisa_uikit_' | sort -u))"
if [[ -n "$unused" ]]; then
  echo "uikit: the backend exports callbacks no shim fragment calls:" >&2
  echo "$unused" >&2
  exit 1
fi
# The shim's own entry points must likewise be exactly what Elisa declared
# extern; an unresolved one would only surface when a device build links.
unresolved="$(comm -23 \
  <(nm -gu "$ELISA_OBJECT" | awk '{print $NF}' | grep '^_elisa_uikit_' | sort -u) \
  <(nm -g "$SHIM_OBJECT" | awk '$2 ~ /^[TDBSC]$/ {print $3}' | grep '^_elisa_uikit_' | sort -u))"
if [[ -n "$unresolved" ]]; then
  echo "uikit: the backend calls shim entry points the shim does not define:" >&2
  echo "$unresolved" >&2
  exit 1
fi

# The framework calls the paint path actually makes must reach CoreText and
# CoreGraphics rather than a native reimplementation.
set +o pipefail
for symbol in CTFontCreateUIFontForLanguage CTLineDraw CGColorCreateGenericRGB \
              CGBitmapContextCreate CGImageDestinationFinalize; do
  nm -gu "$ELISA_OBJECT" | grep "^_${symbol}\$" >/dev/null || {
    echo "uikit: expected undefined framework symbol $symbol" >&2
    exit 1
  }
done
set -o pipefail

SNAPSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-uikit.XXXXXX")"
trap 'rm -rf "$SNAPSHOT_DIR"' EXIT
FIRST="$SNAPSHOT_DIR/frame.png"
SECOND="$SNAPSHOT_DIR/frame-second.png"
ELISA_UI_SMOKE_FRAMES=1 ELISA_UI_SNAPSHOT="$FIRST" "$BIN"
ELISA_UI_SMOKE_FRAMES=1 ELISA_UI_SNAPSHOT="$SECOND" "$BIN"
[[ -s "$FIRST" && -s "$SECOND" ]]
# 393x852 logical points at the default 3x device scale.
file "$FIRST" | grep -q 'PNG image data, 1179 x 2556'
first_digest="$(shasum -a 256 "$FIRST" | awk '{print $1}')"
second_digest="$(shasum -a 256 "$SECOND" | awk '{print $1}')"
[[ -n "$first_digest" && "$first_digest" == "$second_digest" ]] || {
  echo "uikit: fresh-process PNG digest mismatch (first=$first_digest second=$second_digest)" >&2
  exit 12
}
echo "uikit: fresh-process PNG digest verified sha256=$second_digest"
echo "uikit: simulator and device builds, ABI agreement, off-screen PNG frame and boundary guards passed"
