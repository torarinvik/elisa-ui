#!/usr/bin/env bash
# Run the UIKit backends on a real iOS simulator and check what UIKit delivered.
#
# check_uikit.sh proves the framework's own decisions and that the products
# link. This proves the other half: that a booted iOS actually launches them,
# paints them, and delivers the facts those decisions are made from -- surface
# size, display scale, safe-area insets, interface style, contrast, Dynamic
# Type and the application lifecycle.
#
# examples/uikit_smoke prints one line whenever a reported fact changes, so the
# assertions below read what reached Elisa rather than inferring it from pixels.
#
# Skips itself when no iOS runtime is installed; install one with
#   xcodebuild -downloadPlatform iOS
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${ELISA_UI_SIMULATOR_NAME:-elisa-ui-check}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "uikit simulator: skipped (not macOS)"
  exit 0
fi
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS "; then
  echo "uikit simulator: skipped (no iOS runtime; install with 'xcodebuild -downloadPlatform iOS')"
  exit 0
fi

RUNTIME_ID="$(xcrun simctl list runtimes 2>/dev/null | awk '/^iOS /{print $NF}' | tail -1)"
DEVICE_TYPE="$(xcrun simctl list devicetypes 2>/dev/null | awk -F'[()]' '/iPhone 1[5-9]/{print $2}' | tail -1)"
[[ -n "$RUNTIME_ID" && -n "$DEVICE_TYPE" ]] || { echo "uikit simulator: no usable runtime/device type" >&2; exit 1; }

# Reuse the check's own device so a developer's simulators are left alone.
UDID="$(xcrun simctl list devices 2>/dev/null | awk -v name="$DEVICE_NAME" -F'[()]' '$0 ~ name {print $2; exit}')"
if [[ -z "$UDID" ]]; then
  UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
fi
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
until xcrun simctl list devices 2>/dev/null | grep "$UDID" | grep -q Booted; do sleep 1; done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/elisa-ui-sim.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "uikit simulator: $1" >&2; exit 1; }

# A fact line looks like:
#   ELISA-UI-SMOKE width=402.0 ... phase=2.0
field() { sed -n "s/.*[[:space:]]$2=\([^[:space:]]*\).*/\1/p" "$1" | tail -1; }
wait_for() {
  local file="$1" pattern="$2" limit="${3:-60}"
  for _ in $(seq "$limit"); do
    grep -q "$pattern" "$file" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

# --- The smoke app: what UIKit actually delivered ----------------------

bash "$ROOT/scripts/build_uikit.sh" uikit_smoke simulator canvas >/dev/null
SMOKE_BUNDLE=org.elisa-ui.uikit_smoke.canvas
xcrun simctl terminate "$UDID" "$SMOKE_BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$ROOT/build/ios/simulator/canvas/uikit_smoke_uikit.app" >/dev/null
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" content_size medium >/dev/null 2>&1 || true
CONSOLE="$WORK/smoke.txt"
# --console-pty keeps a reader attached to the device for as long as it runs.
# Leaving one behind makes the next gate's install race with it, so its pid is
# kept and killed rather than orphaned.
xcrun simctl launch --console-pty "$UDID" "$SMOKE_BUNDLE" >"$CONSOLE" 2>&1 &
CONSOLE_PID=$!
cleanup_console() { kill "$CONSOLE_PID" 2>/dev/null || true; }
trap 'cleanup_console; rm -rf "$WORK"' EXIT
wait_for "$CONSOLE" "ELISA-UI-SMOKE" || fail "the app never reported a frame"

# The scene's geometry has to reach Elisa, not a size compiled into the app.
width="$(field "$CONSOLE" width)"
scale="$(field "$CONSOLE" scale)"
inset_top="$(field "$CONSOLE" inset_top)"
inset_bottom="$(field "$CONSOLE" inset_bottom)"
awk -v w="$width" 'BEGIN{exit !(w > 300 && w < 500)}' || fail "implausible surface width: $width"
awk -v s="$scale" 'BEGIN{exit !(s >= 2)}' || fail "implausible display scale: $scale"
# Every device this check runs on has a notch and a home indicator, so a zero
# inset means the safe area never arrived.
awk -v t="$inset_top" 'BEGIN{exit !(t > 0)}' || fail "the safe-area top inset never arrived: $inset_top"
awk -v b="$inset_bottom" 'BEGIN{exit !(b > 0)}' || fail "the safe-area bottom inset never arrived: $inset_bottom"
# The scene reports its first frame before the delegate has said the app
# became active, so this is a wait rather than a reading of the first line.
wait_for "$CONSOLE" "phase=2.0" || fail "the app never became active"
# The device keeps its appearance between runs, and a change made just before
# launch can land after the first frame. Ask again and wait, the same way the
# dark-mode check below does.
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
wait_for "$CONSOLE" "dark=no" || fail "the light appearance never arrived"

# A real trait change, delivered by UIKit's own registration.
xcrun simctl ui "$UDID" appearance dark >/dev/null
wait_for "$CONSOLE" "dark=yes" || fail "a dark-mode trait change never reached Elisa"

# Dynamic Type, as the scaled body size rather than a category name.
xcrun simctl ui "$UDID" content_size accessibility-extra-large >/dev/null
wait_for "$CONSOLE" "text_scale=[2-9]" || fail "a Dynamic Type change never reached Elisa"
xcrun simctl ui "$UDID" content_size medium >/dev/null

# The application lifecycle, driven by really backgrounding the app.
xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null 2>&1 || true
wait_for "$CONSOLE" "phase=3.0" || fail "resigning active never reached Elisa"
xcrun simctl launch "$UDID" "$SMOKE_BUNDLE" >/dev/null
wait_for "$CONSOLE" "phase=2.0" 30 || fail "becoming active again never reached Elisa"
xcrun simctl terminate "$UDID" "$SMOKE_BUNDLE" >/dev/null 2>&1 || true
cleanup_console
echo "uikit simulator: surface $width@${scale}x, safe area ${inset_top}/${inset_bottom}, appearance, Dynamic Type and lifecycle all reached Elisa"

# --- Both backends launch and paint ------------------------------------

for backend in canvas controls; do
  case "$backend" in
    canvas) bundle=org.elisa-ui.hello.canvas; app="$ROOT/build/ios/simulator/canvas/hello_uikit.app" ;;
    controls) bundle=org.elisa-ui.hello.controls; app="$ROOT/build/ios/simulator/controls/hello_uikit_controls.app" ;;
  esac
  bash "$ROOT/scripts/build_uikit.sh" hello simulator "$backend" >/dev/null
  xcrun simctl terminate "$UDID" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$app" >/dev/null
  xcrun simctl launch "$UDID" "$bundle" >/dev/null
  # Give the scene a moment to lay out and paint its first frame.
  #
  # `launchctl list | grep -q` is a trap under pipefail: grep can close the
  # pipe on a match before launchctl has finished writing, and the pipeline
  # then reports launchctl's SIGPIPE rather than grep's success. Capture the
  # table first and search that.
  running=""
  for _ in $(seq 10); do
    sleep 1
    running="$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)"
    case "$running" in *"$bundle"*) break ;; esac
  done
  case "$running" in
    *"$bundle"*) ;;
    *) fail "the $backend app is not running after launch" ;;
  esac
  shot="$WORK/$backend.png"
  xcrun simctl io "$UDID" screenshot "$shot" >/dev/null 2>&1
  [[ -s "$shot" ]] || fail "no screenshot for the $backend app"
  # A blank screen compresses to almost nothing. A painted one does not, so
  # this catches a launch that renders an empty window.
  size="$(stat -f%z "$shot")"
  [[ "$size" -gt 40000 ]] || fail "the $backend app rendered a blank screen ($size bytes)"
  xcrun simctl terminate "$UDID" "$bundle" >/dev/null 2>&1 || true
  echo "uikit simulator: the $backend app launched and painted ($size byte screenshot)"
done

# Leave the device as this gate found it, so a rerun starts from the same
# place rather than inheriting the settings the last one exercised.
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" content_size medium >/dev/null 2>&1 || true
echo "uikit simulator: both iOS backends run on a booted device"
