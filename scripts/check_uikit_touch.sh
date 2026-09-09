#!/usr/bin/env bash
# A real touch, on a real simulator.
#
# simctl cannot inject one, so this drives XCUIApplication, whose taps go
# through the simulator's own HID pipeline -- the same path a finger takes.
# That makes one test cover the whole chain: the semantic tree Elisa publishes
# is visible to iOS at all (XCUI can only see a custom-painted canvas through
# its accessibility elements), UIKit delivers the touch to the view, the
# framework routes it into the retained model, the application callback runs,
# and the repainted frame republishes the semantics the assertion reads back.
#
# There is no Xcode project here, so the runner is assembled by hand from the
# XCTRunner.app template Xcode ships, with the test frameworks embedded and an
# .xctestrun written out. That is all this script does that an Xcode scheme
# would otherwise do for us.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${ELISA_UI_SIMULATOR_NAME:-elisa-ui-check}"
PLATFORM=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer
RUNNER_TEMPLATE="$PLATFORM/Library/Xcode/Agents/XCTRunner.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "uikit touch: skipped (not macOS)"
  exit 0
fi
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS "; then
  echo "uikit touch: skipped (no iOS runtime; install with 'xcodebuild -downloadPlatform iOS')"
  exit 0
fi
if [[ ! -d "$RUNNER_TEMPLATE" ]]; then
  echo "uikit touch: skipped (no XCTRunner template in this Xcode)"
  exit 0
fi

RUNTIME_ID="$(xcrun simctl list runtimes 2>/dev/null | awk '/^iOS /{print $NF}' | tail -1)"
DEVICE_TYPE="$(xcrun simctl list devicetypes 2>/dev/null | awk -F'[()]' '/iPhone 1[5-9]/{print $2}' | tail -1)"
UDID="$(xcrun simctl list devices 2>/dev/null | awk -v name="$DEVICE_NAME" -F'[()]' '$0 ~ name {print $2; exit}')"
if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
fi
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
until xcrun simctl list devices 2>/dev/null | grep "$UDID" | grep -q Booted; do sleep 1; done

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
OUT="$ROOT/build/ios/uitest"
rm -rf "$OUT"
mkdir -p "$OUT"

# --- The test bundle ---------------------------------------------------

XCTEST="$OUT/ElisaUiKitTouchTests.xctest"
mkdir -p "$XCTEST"
xcrun --sdk iphonesimulator clang -target "$(uname -m)-apple-ios17.0-simulator" -isysroot "$SDK" \
  -fobjc-arc -bundle -Wall -Wextra -Werror \
  -F "$PLATFORM/Library/Frameworks" -framework XCTest -framework XCUIAutomation -framework Foundation \
  -o "$XCTEST/ElisaUiKitTouchTests" "$ROOT/test/ios/ElisaUiKitTouchTests.m"
PLIST="$XCTEST/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleExecutable -string "ElisaUiKitTouchTests" "$PLIST"
plutil -insert CFBundleIdentifier -string "org.elisa-ui.touchtests" "$PLIST"
plutil -insert CFBundleName -string "ElisaUiKitTouchTests" "$PLIST"
plutil -insert CFBundlePackageType -string "BNDL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "1.0" "$PLIST"
plutil -insert CFBundleVersion -string "1" "$PLIST"
plutil -insert CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$PLIST"
plutil -insert MinimumOSVersion -string "17.0" "$PLIST"

# --- The runner --------------------------------------------------------

RUNNER="$OUT/ElisaUiKitTouchTests-Runner.app"
cp -R "$RUNNER_TEMPLATE" "$RUNNER"
mkdir -p "$RUNNER/PlugIns" "$RUNNER/Frameworks"
cp -R "$XCTEST" "$RUNNER/PlugIns/"
plutil -replace CFBundleName -string "ElisaUiKitTouchTests-Runner" "$RUNNER/Info.plist"
plutil -replace CFBundleIdentifier -string "org.elisa-ui.touchtests.xctrunner" "$RUNNER/Info.plist"
# The template ships CFBundleExecutable as the literal $(WRAPPEDPRODUCTNAME),
# which Xcode would substitute. Name the executable the template actually
# contains, or the install fails with "missing its bundle executable".
plutil -replace CFBundleExecutable -string "XCTRunner" "$RUNNER/Info.plist"
# XCTRunner links these by @rpath; an Xcode scheme embeds them for us.
for framework in XCTest XCUIAutomation Testing _Testing_CoreGraphics _Testing_CoreImage _Testing_Foundation _Testing_UIKit; do
  [[ -d "$PLATFORM/Library/Frameworks/$framework.framework" ]] &&
    cp -R "$PLATFORM/Library/Frameworks/$framework.framework" "$RUNNER/Frameworks/"
done
for framework in XCTestCore XCTAutomationSupport XCTestSupport XCUnit; do
  [[ -d "$PLATFORM/Library/PrivateFrameworks/$framework.framework" ]] &&
    cp -R "$PLATFORM/Library/PrivateFrameworks/$framework.framework" "$RUNNER/Frameworks/"
done
cp "$PLATFORM/usr/lib/libXCTestSwiftSupport.dylib" "$RUNNER/Frameworks/" 2>/dev/null || true
cp "$PLATFORM/usr/lib/lib_TestingInterop.dylib" "$RUNNER/Frameworks/" 2>/dev/null || true
codesign --force --sign - --entitlements "$RUNNER/RunnerEntitlements.plist" "$RUNNER" >/dev/null 2>&1

# --- The app under test ------------------------------------------------

bash "$ROOT/scripts/build_uikit.sh" uikit_smoke simulator canvas >/dev/null
cp -R "$ROOT/build/ios/simulator/canvas/uikit_smoke_uikit.app" "$OUT/"
xcrun simctl uninstall "$UDID" org.elisa-ui.uikit_smoke.canvas >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" org.elisa-ui.touchtests.xctrunner >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$OUT/uikit_smoke_uikit.app" >/dev/null

# Deliberately NO TestingEnvironmentVariables: libXCTestBundleInject is how a
# unit-test bundle is loaded into its host app, and injecting it into a UI test
# runner that already loads XCTest fails with "Cannot initiate shared session
# more than once."
cat > "$OUT/elisa.xctestrun" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>__xctestrun_metadata__</key>
  <dict><key>FormatVersion</key><integer>1</integer></dict>
  <key>ElisaUiKitTouchTests</key>
  <dict>
    <key>IsUITestBundle</key><true/>
    <key>IsXCTRunnerHostedTestBundle</key><true/>
    <key>TestBundlePath</key><string>__TESTHOST__/PlugIns/ElisaUiKitTouchTests.xctest</string>
    <key>TestHostPath</key><string>$RUNNER</string>
    <key>UITargetAppPath</key><string>$OUT/uikit_smoke_uikit.app</string>
    <key>ProductModuleName</key><string>ElisaUiKitTouchTests</string>
    <key>SystemAttachmentLifetime</key><string>deleteOnSuccess</string>
    <key>UserAttachmentLifetime</key><string>deleteOnSuccess</string>
  </dict>
</dict>
</plist>
PLIST
plutil -lint "$OUT/elisa.xctestrun" >/dev/null

LOG="$OUT/xcodebuild.log"
if ! xcodebuild test-without-building -xctestrun "$OUT/elisa.xctestrun" \
     -destination "platform=iOS Simulator,id=$UDID" >"$LOG" 2>&1; then
  echo "uikit touch: the UI test failed" >&2
  grep -E "error:|Failing tests|Underlying Error" "$LOG" >&2 | head -10 || true
  exit 1
fi
grep -q "Executed 1 test, with 0 failures" "$LOG" || {
  echo "uikit touch: the UI test did not report a pass" >&2
  tail -20 "$LOG" >&2
  exit 1
}
echo "uikit touch: a real system-level touch reached the retained model and came back through the semantic tree"
