#!/usr/bin/env bash
# Exercise UIKit PhotosUI and Files selection through the real simulator UI.
# This gate owns a newly-created simulator and never reuses developer devices.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/simctl_query.sh"
PLATFORM=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer
RUNNER_TEMPLATE="$PLATFORM/Library/Xcode/Agents/XCTRunner.app"
DEVICE_NAME="elisa-picker-test-$(date +%s)-$$"
UDID=""
created=0

cleanup() {
  if [[ "$created" == 1 && -n "$UDID" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM HUP

[[ "$(uname -s)" == Darwin ]] || { echo "uikit services: requires macOS" >&2; exit 2; }
RUNTIME_LIST="$(simctl_query list runtimes)"
RUNTIME_ID="$(awk '/^iOS /{print $NF}' <<<"$RUNTIME_LIST" | tail -1)"
[[ -n "$RUNTIME_ID" ]] || { echo "uikit services: no iOS simulator runtime" >&2; exit 2; }
[[ -d "$RUNNER_TEMPLATE" ]] || { echo "uikit services: no XCTest runner template in this Xcode" >&2; exit 2; }
DEVICE_TYPES="$(simctl_query list devicetypes)"
DEVICE_TYPE="$(awk -F'[()]' '/iPhone 1[5-9]/{print $2}' <<<"$DEVICE_TYPES" | tail -1)"
[[ -n "$DEVICE_TYPE" ]] || { echo "uikit services: no supported iPhone simulator device type" >&2; exit 2; }

UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
created=1
xcrun simctl boot "$UDID"
OUT="$ROOT/build/ios/picker-uitest-$DEVICE_NAME"
mkdir -p "$OUT"

# Wait for CoreSimulator to finish first boot before installing the app. Keep
# the verbose migration log local so the gate's normal output stays readable.
if ! xcrun simctl bootstatus "$UDID" -b >"$OUT/boot.log" 2>&1; then
  tail -40 "$OUT/boot.log" >&2
  exit 1
fi

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
XCTEST="$OUT/ElisaUiKitPickerTests.xctest"
mkdir -p "$XCTEST"
xcrun --sdk iphonesimulator clang -target "$(uname -m)-apple-ios17.0-simulator" -isysroot "$SDK" \
  -fobjc-arc -bundle -Wall -Wextra -Werror \
  -F "$PLATFORM/Library/Frameworks" -framework XCTest -framework XCUIAutomation -framework Foundation \
  -o "$XCTEST/ElisaUiKitPickerTests" "$ROOT/test/ios/ElisaUiKitPickerTests.m"
plutil -create xml1 "$XCTEST/Info.plist"
plutil -insert CFBundleExecutable -string "ElisaUiKitPickerTests" "$XCTEST/Info.plist"
plutil -insert CFBundleIdentifier -string "org.elisa-ui.pickertests" "$XCTEST/Info.plist"
plutil -insert CFBundleName -string "ElisaUiKitPickerTests" "$XCTEST/Info.plist"
plutil -insert CFBundlePackageType -string "BNDL" "$XCTEST/Info.plist"
plutil -insert CFBundleShortVersionString -string "1.0" "$XCTEST/Info.plist"
plutil -insert CFBundleVersion -string "1" "$XCTEST/Info.plist"
plutil -insert CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$XCTEST/Info.plist"
plutil -insert MinimumOSVersion -string "17.0" "$XCTEST/Info.plist"

RUNNER="$OUT/ElisaUiKitPickerTests-Runner.app"
cp -R "$RUNNER_TEMPLATE" "$RUNNER"
mkdir -p "$RUNNER/PlugIns" "$RUNNER/Frameworks"
cp -R "$XCTEST" "$RUNNER/PlugIns/"
plutil -replace CFBundleName -string "ElisaUiKitPickerTests-Runner" "$RUNNER/Info.plist"
plutil -replace CFBundleIdentifier -string "org.elisa-ui.pickertests.xctrunner" "$RUNNER/Info.plist"
plutil -replace CFBundleExecutable -string "XCTRunner" "$RUNNER/Info.plist"
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

# The fresh iOS runtime contains sample Photos assets. The Files picker gets a
# harmless project doc in the smoke app's On My iPhone location.
if [[ -n "${ELISA_UI_PICKER_APP_OVERRIDE:-}" ]]; then
  # Diagnostic escape hatch for running an already-built app when a concurrent
  # Stage1 change makes the current compiler output non-deterministic.
  APP="$ELISA_UI_PICKER_APP_OVERRIDE"
else
  bash "$ROOT/scripts/build_uikit.sh" uikit_services_smoke simulator canvas >/dev/null
  APP="$ROOT/build/ios/simulator/canvas/uikit_services_smoke_uikit.app"
fi
[[ -d "$APP" ]] || { echo "uikit services: picker app not found at $APP" >&2; exit 2; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" == "org.elisa-ui.uikit_services_smoke.canvas" ]] || {
  echo "uikit services: picker app has the wrong bundle identifier" >&2
  exit 2
}
xcrun simctl install "$UDID" "$APP"
APP_DATA="$(xcrun simctl get_app_container "$UDID" org.elisa-ui.uikit_services_smoke.canvas data)"
mkdir -p "$APP_DATA/Documents"
cp "$ROOT/docs/ui-services.md" "$APP_DATA/Documents/elisa-picker-smoke.txt"

cat >"$OUT/elisa.xctestrun" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>__xctestrun_metadata__</key>
  <dict><key>FormatVersion</key><integer>1</integer></dict>
  <key>ElisaUiKitPickerTests</key>
  <dict>
    <key>IsUITestBundle</key><true/>
    <key>IsXCTRunnerHostedTestBundle</key><true/>
    <key>TestBundlePath</key><string>__TESTHOST__/PlugIns/ElisaUiKitPickerTests.xctest</string>
    <key>TestHostPath</key><string>$RUNNER</string>
    <key>UITargetAppPath</key><string>$APP</string>
    <key>ProductModuleName</key><string>ElisaUiKitPickerTests</string>
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
  echo "uikit services: picker UI test failed; diagnostic log: $LOG" >&2
  grep -E "error:|Failing tests|Underlying Error|XCTAssert" "$LOG" >&2 | head -20 || true
  exit 1
fi
grep -q "Executed 1 test, with 0 failures" "$LOG" || {
  echo "uikit services: XCTest did not report one passing picker test; diagnostic log: $LOG" >&2
  tail -30 "$LOG" >&2
  exit 1
}
echo "uikit services: PhotosUI and Files selections were read and explicitly released on a dedicated simulator"
