#!/usr/bin/env bash
# Validate the Android native-controls backend.
#
# The Skia canvas has its own Android gate, but the android.widget backend has
# a different package, Java surface and JNI boundary. Build and inspect that
# product independently so a passing canvas APK cannot hide a stale controls
# ABI. If a device is attached, launch the real Activity and read a screenshot
# as a small runtime proof; the build half remains useful on a host without a
# device.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
EXAMPLE="${1:-showcase}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"

if [[ ! -d "$SDK" ]]; then
  echo "android controls: skipped (no Android SDK at $SDK)"
  exit 0
fi
if [[ -z "$NDK" || ! -d "$NDK" ]]; then
  echo "android controls: skipped (no NDK under $SDK/ndk)"
  exit 0
fi

[[ -x "$STAGE1/bin/elisac-stage1" ]] || {
  echo "android controls: no stage1 product at $STAGE1/bin/elisac-stage1" >&2
  exit 2
}

# --- 1. Build the controls APK with the selected compiler -----------------
bash "$ROOT/scripts/build_android_controls.sh" "$EXAMPLE" >/dev/null
OUT="$ROOT/build/android-controls/$EXAMPLE"
APK="$OUT/$EXAMPLE-controls.apk"
SO="$OUT/apk/lib/arm64-v8a/lib$EXAMPLE.so"
[[ -f "$APK" && -f "$SO" ]] || {
  echo "android controls: the build produced no APK or native library" >&2
  exit 1
}

# Read ELF facts with the NDK tool, accepting either prebuilt host tag.
READELF=""
for candidate in "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-readelf; do
  if [[ -x "$candidate" ]]; then
    READELF="$candidate"
    break
  fi
done
[[ -n "$READELF" ]] || READELF="$(command -v llvm-readelf || true)"
[[ -x "$READELF" ]] || {
  echo "android controls: llvm-readelf is required" >&2
  exit 2
}

symbols="$("$READELF" --dyn-symbols "$SO")"
for entry in elisa_android_controls_start elisa_android_controls_resize \
             elisa_android_controls_stop elisa_android_controls_event \
             elisa_android_controls_text \
             Java_org_elisa_1ui_ElisaControlsActivity_nativeStart \
             Java_org_elisa_1ui_ElisaControlsActivity_nativeResize \
             Java_org_elisa_1ui_ElisaControlsActivity_nativeStop \
             Java_org_elisa_1ui_ElisaControls_nativeControlEvent \
             Java_org_elisa_1ui_ElisaControls_nativeControlText; do
  grep -q " $entry$" <<<"$symbols" || {
    echo "android controls: $entry is not exported from lib$EXAMPLE.so" >&2
    exit 1
  }
done
dynamic="$("$READELF" --dynamic "$SO")"
if grep -q "libc++_shared\\|libskia" <<<"$dynamic"; then
  echo "android controls: native-controls APK links an unintended shared/custom renderer" >&2
  exit 1
fi
echo "android controls: JNI and Elisa entry points exported; no Skia/shared C++ runtime dependency"

# The loader maps this library straight from the APK. Keep the same 16 KB
# alignment and uncompressed-entry checks as the painted Android backend.
listing="$(unzip -lv "$APK" "lib/arm64-v8a/lib$EXAMPLE.so")"
grep -q "Stored" <<<"$listing" || {
  echo "android controls: the native library is compressed in the APK" >&2
  exit 1
}
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)"
[[ -x "$BUILD_TOOLS/zipalign" ]] || {
  echo "android controls: zipalign is required" >&2
  exit 2
}
"$BUILD_TOOLS/zipalign" -c -P 16 4 "$APK" >/dev/null || {
  echo "android controls: the APK is not 16 KB page aligned" >&2
  exit 1
}

# count in ElisaControls is a live count, so it cannot bound slot-indexed
# handles after reconciliation leaves holes. Keep this source-level assertion
# next to the package gate: it prevents the exact regression from being hidden
# by an APK that only exercises a prefix of the handle table.
JAVA="$ROOT/src/platform/android/java/org/elisa_ui/ElisaControls.java"
grep -Fq 'handle <= 0 || handle > MAX_CONTROLS ? null : views[handle - 1]' "$JAVA" || {
  echo "android controls: handle lookup is not bounded by the slot table" >&2
  exit 1
}
if grep -Fq 'handle <= 0 || handle > count ?' "$JAVA"; then
  echo "android controls: handle lookup still treats live count as highest slot" >&2
  exit 1
fi

grep -q 'android:hasCode="true"' "$OUT/AndroidManifest.xml" || {
  echo "android controls: manifest does not carry the Java bridge" >&2
  exit 1
}
apk_listing="$(unzip -l "$APK")"
grep -q 'classes.dex' <<<"$apk_listing" || {
  echo "android controls: APK contains no classes.dex" >&2
  exit 1
}
echo "android controls: $(basename "$APK") is stored, aligned, and carries Java code"

# --- 2. Optional device half ----------------------------------------------
ADB="${ADB:-$SDK/platform-tools/adb}"
if [[ ! -x "$ADB" ]] || ! "$ADB" devices | grep -q "	device$"; then
  echo "android controls: skipped the device half (nothing attached)"
  exit 0
fi

PACKAGE="org.elisa_ui.${EXAMPLE}_controls"
ACTIVITY="org.elisa_ui.ElisaControlsActivity"
"$ADB" install -r "$APK" >/dev/null
"$ADB" shell am force-stop "$PACKAGE" || true
"$ADB" shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null
pid=""
for _ in $(seq 1 20); do
  pid="$("$ADB" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')"
  [[ -n "$pid" ]] && break
  sleep 1
done
[[ -n "$pid" ]] || {
  echo "android controls: Activity did not stay alive after launch" >&2
  "$ADB" logcat -d -t 120 -s AndroidRuntime '*:S' >&2 || true
  exit 1
}

SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/elisa-ui-android-controls.XXXXXX.png")"
trap 'rm -f "$SNAPSHOT"; "$ADB" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true' EXIT
"$ADB" exec-out screencap -p >"$SNAPSHOT"
[[ -s "$SNAPSHOT" ]] || {
  echo "android controls: device screenshot is empty" >&2
  exit 1
}
size="$(stat -f%z "$SNAPSHOT" 2>/dev/null || stat -c%s "$SNAPSHOT")"
[[ "$size" -gt 10000 ]] || {
  echo "android controls: device screenshot is suspiciously small ($size bytes)" >&2
  exit 1
}
echo "android controls: real Activity launched and painted ($size byte screenshot)"
