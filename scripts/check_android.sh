#!/usr/bin/env bash
# Validate the Android backend.
#
# Two halves, and the second one is optional:
#
#   1. The whole product is cross-compiled and packaged for arm64. A link with
#      --no-undefined is the strongest available proof that the Elisa object,
#      the NativeActivity host and the Skia shims agree: every callback the
#      host calls must be defined by Elisa, and every entry point Elisa
#      declared extern must exist in the host. The APK is then read back to
#      check the three things that make it load at all -- the library at its
#      ABI path, stored rather than deflated, and 16 KB page alignment.
#   2. If a device or emulator is attached, it is installed, launched and
#      asked what it drew. A frame that says it is made of one colour is a
#      window that came up blank, which is the failure this half exists for.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="${1:-storefront}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
SKIA_ROOT="${SKIA_ROOT:-}"
SKIA_OUT="${SKIA_ANDROID_OUT:-$SKIA_ROOT/out/elisa-android-arm64}"

# A missing toolchain is UNKNOWN, not PASSED. Say which part is missing.
if [[ ! -d "$SDK" ]]; then
  echo "android: skipped (no Android SDK at $SDK)"
  exit 0
fi
if [[ -z "$NDK" || ! -d "$NDK" ]]; then
  echo "android: skipped (no NDK under $SDK/ndk)"
  exit 0
fi
# TWO DIFFERENT SKIPS, because they ask for different things. A machine with no
# Android Skia has to build it; a machine that HAS it and was not told where is
# a gate silently declining to run on a machine that could have passed it --
# which is how both Android backends stayed unverified while every suite ran
# green.
if [[ -z "$SKIA_ROOT" ]]; then
  echo "android: skipped (SKIA_ROOT not set; it is needed even though only the canvas backend uses Skia)"
  exit 0
fi
if [[ ! -f "$SKIA_OUT/libskia.a" ]]; then
  echo "android: skipped (no Android Skia at $SKIA_OUT; run scripts/build_skia_android.sh)"
  exit 0
fi

# --- 1. Build and read the package back --------------------------------
bash "$ROOT/scripts/build_android.sh" "$EXAMPLE" >/dev/null
ANDROID_OUT_ROOT="${ELISA_UI_ANDROID_OUT_ROOT:-$ROOT/build/android}"
OUT="$ANDROID_OUT_ROOT/$EXAMPLE"
APK="$OUT/$EXAMPLE.apk"
SO="$OUT/lib$EXAMPLE.so"
[[ -f "$APK" && -f "$SO" ]] || { echo "android: the build produced no package" >&2; exit 1; }

READELF="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
if [[ ! -x "$READELF" ]]; then
  for candidate in "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-readelf; do
    if [[ -x "$candidate" ]]; then
      READELF="$candidate"
      break
    fi
  done
fi
[[ -x "$READELF" ]] || READELF="$(command -v llvm-readelf || true)"
[[ -x "$READELF" ]] || { echo "android: llvm-readelf is required to verify exported entry points" >&2; exit 1; }
symbols="$("$READELF" --dyn-symbols "$SO")"
# android_main is what NativeActivity looks up; the rest is the ABI the
# host calls back through, and a missing one is a blank window at runtime.
for entry in android_main elisa_android_start elisa_android_resize elisa_android_render \
             elisa_android_touch elisa_android_contact elisa_android_text_purpose elisa_android_scroll elisa_android_frame_delay \
             elisa_android_lifecycle elisa_android_key elisa_android_text elisa_android_keyboard_insets \
             elisa_android_wants_keyboard elisa_android_back \
             elisa_android_permission_result elisa_android_permission_sync \
             elisa_android_picker_result; do
  grep -q " $entry\$" <<<"$symbols" || { echo "android: $entry is not exported from lib$EXAMPLE.so" >&2; exit 1; }
done
# C++ was linked statically on purpose: Android ships no libc++_shared, and
# the NativeActivity APK keeps its Java side limited to the IME bridge.
dynamic_symbols="$("$READELF" --dynamic "$SO")"
if grep -q "libc++_shared" <<<"$dynamic_symbols"; then
  echo "android: lib$EXAMPLE.so needs libc++_shared, which this APK cannot supply" >&2
  exit 1
fi
echo "android: entry points exported, C++ linked in"

# extractNativeLibs="false" means the loader maps the library straight out of
# the APK, which it can only do if the entry is stored and page-aligned.
listing="$(unzip -lv "$APK" "lib/arm64-v8a/lib$EXAMPLE.so")"
grep -q "Stored" <<<"$listing" || { echo "android: the library is compressed in the APK" >&2; exit 1; }
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)"
"$BUILD_TOOLS/zipalign" -c -P 16 4 "$APK" >/dev/null || {
  echo "android: the APK is not 16 KB page aligned" >&2; exit 1; }
echo "android: $(basename "$APK") is stored and 16 KB aligned"

# The clipboard bridge borrows the NativeActivity only while its lifecycle is
# alive. Keep the detach at both native exit paths: a raw activity pointer that
# survives teardown turns a late paste into a use-after-free.
grep -Fq 'elisa_android_clipboard_attach(nullptr)' "$ROOT/src/platform/android/android_skia_host.cpp" || {
  echo "android: clipboard activity is not detached during host teardown" >&2
  exit 1
}
# Every JNI lookup in the clipboard bridge must be guarded before a method is
# queried or called. A missing framework class/method is a recoverable
# clipboard-unavailable state, not a CheckJNI abort that takes down the app.
CLIPBOARD="$ROOT/src/platform/android/android_clipboard.cpp"
grep -Fq 'if (activity_class == nullptr || failed(env))' "$CLIPBOARD" || {
  echo "android: clipboard activity class lookup is not guarded" >&2
  exit 1
}
grep -Fq 'if (manager_class != nullptr && !failed(env))' "$CLIPBOARD" || {
  echo "android: clipboard manager class lookup is not guarded" >&2
  exit 1
}
grep -Fq 'if (clip_class != nullptr && !failed(env))' "$CLIPBOARD" || {
  echo "android: clipboard clip class lookup is not guarded" >&2
  exit 1
}
IME="$ROOT/src/platform/android/android_ime_jni.c"
grep -Fq 'if (elisa_ime_failed(env)) return;' "$IME" || {
  echo "android: IME string conversion does not clear JNI failures" >&2
  exit 1
}
grep -Fq 'value == NULL ? "" : value' "$IME" || {
  echo "android: IME diagnostics do not guard a null framework string" >&2
  exit 1
}
HOST="$ROOT/src/platform/android/android_skia_host.cpp"
grep -Fq 'bool pixels_valid = false;' "$HOST" || {
  echo "android: frame tracing does not track SkPixmap validity" >&2
  exit 1
}
grep -Fq 'tracing() && pixels_valid ? sampled_colors(pixels) : 0' "$HOST" || {
  echo "android: frame tracing may sample an uninitialized SkPixmap" >&2
  exit 1
}
grep -Fq 'active_pointer_id' "$HOST" || {
  echo "android: touch routing does not retain pointer identity" >&2
  exit 1
}
grep -Fq 'AMOTION_EVENT_ACTION_POINTER_DOWN' "$HOST" || {
  echo "android: touch routing does not handle a secondary pointer" >&2
  exit 1
}
grep -Fq 'pointer_index_for_id' "$HOST" || {
  echo "android: motion coordinates still assume pointer slot zero" >&2
  exit 1
}
BACK_QUEUE="$ROOT/src/platform/android/android_back_queue.cpp"
grep -Fq 'pending_back_requests.exchange(0' "$BACK_QUEUE" || {
  echo "android: Activity back callbacks do not return to the native owner thread" >&2
  exit 1
}
grep -Fq 'OnBackInvokedCallback' "$ROOT/src/platform/android/java/org/elisa_ui/ElisaCanvasActivity.java" || {
  echo "android: predictive/system back callback is not registered" >&2
  exit 1
}
JAVA_ACTIVITY="$ROOT/src/platform/android/java/org/elisa_ui/ElisaCanvasActivity.java"
grep -Fq 'preferences.getBoolean(permissionRequestPreference(kind), false)' "$JAVA_ACTIVITY" || {
  echo "android: a fresh service record can bypass the persisted permission anti-prompt gate" >&2
  exit 1
}
grep -Fq 'nativePermissionResult(slot, generation, 3, 1)' "$JAVA_ACTIVITY" || {
  echo "android: a previously requested, still-denied permission is not returned as Denied" >&2
  exit 1
}

# --- 2. A device, if one is attached ------------------------------------
ADB="${ADB:-$SDK/platform-tools/adb}"
if [[ ! -x "$ADB" ]] || ! "$ADB" devices | grep -q "	device$"; then
  echo "android: skipped the device half (nothing attached)"
  exit 0
fi

PACKAGE="org.elisa_ui.$EXAMPLE"
"$ADB" install -r "$APK" >/dev/null
ANDROID_TEST_AVD=0
ROTATION_AUTO=""
ROTATION_USER=""
TRACE_PROPERTY=""
restore_android_test_state() {
  if [[ "$ANDROID_TEST_AVD" == 1 && -n "$ROTATION_AUTO" && -n "$ROTATION_USER" ]]; then
    "$ADB" shell settings put system accelerometer_rotation 0 >/dev/null 2>&1 || true
    "$ADB" shell settings put system user_rotation "$ROTATION_USER" >/dev/null 2>&1 || true
    "$ADB" shell settings put system accelerometer_rotation "$ROTATION_AUTO" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TRACE_PROPERTY" ]]; then
    "$ADB" shell setprop debug.elisa.trace "$TRACE_PROPERTY" >/dev/null 2>&1 || true
  else
    "$ADB" shell setprop debug.elisa.trace 0 >/dev/null 2>&1 || true
  fi
  "$ADB" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
}
trap restore_android_test_state EXIT
if [[ "$("$ADB" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" == 1 ]]; then
  ANDROID_TEST_AVD=1
  ROTATION_AUTO="$("$ADB" shell settings get system accelerometer_rotation 2>/dev/null | tr -d '\r')"
  ROTATION_USER="$("$ADB" shell settings get system user_rotation 2>/dev/null | tr -d '\r')"
  TRACE_PROPERTY="$("$ADB" shell getprop debug.elisa.trace 2>/dev/null | tr -d '\r')"
fi
# LAUNCH AND WATCH, WITH ONE RETRY. This gate failed once inside a loaded suite
# with a log full of rendered frames and no "start -> 1" line -- the host had
# plainly run, and the check that says it did not had been green twice that
# hour. I could not reproduce it: alone, and with the process deliberately left
# alive first, it passes every time. So the cause is not established, and the
# honest response is the one check_uikit_touch.sh already uses for a busy
# device rather than a confident fix for a diagnosis I do not have.
#
# Force-stop is a request, not a fact, and `am start` on a process that is
# still alive RESUMES the activity: the app redraws, so the frame lines appear
# as usual, but the one-time start line does not. Waiting for the process to go
# is strictly better whether or not it was the cause here.
launch_and_watch() {
  "$ADB" shell am force-stop "$PACKAGE"
  for _ in $(seq 1 20); do
    [[ -z "$("$ADB" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')" ]] && break
    sleep 0.5
  done
  # The frame trace is what this half reads; it is off unless asked for.
  "$ADB" shell setprop debug.elisa.trace 1
  "$ADB" logcat -c
  "$ADB" shell am start -n "$PACKAGE/org.elisa_ui.ElisaCanvasActivity" >/dev/null
  for _ in $(seq 1 20); do
    sleep 1
    log="$("$ADB" logcat -d -s elisa-ui)"
    grep -q "colors=" <<<"$log" && break
  done
grep -q "start .* -> 1\$" <<<"$log"
}

if ! launch_and_watch; then
  echo "android: first attempt saw no start line; retrying once in case the device was busy" >&2
  sleep 3
  launch_and_watch || { echo "android: the host never started"; echo "$log" >&2; exit 1; }
fi
frame="$(grep "colors=" <<<"$log" | tail -1)"
[[ -n "$frame" ]] || { echo "android: no frame was drawn"; echo "$log" >&2; exit 1; }
colors="$(sed -n 's/.*colors=\([0-9]*\).*/\1/p' <<<"$frame")"
[[ "$colors" -gt 64 ]] || { echo "android: the frame is $colors colour(s) -- a blank window" >&2; exit 1; }
echo "android: ${frame#*elisa-ui: }"

if [[ "$ANDROID_TEST_AVD" == 1 && "$ROTATION_AUTO" =~ ^[01]$ && "$ROTATION_USER" =~ ^[0-3]$ ]]; then
  wait_for_lifecycle_log() {
    local pattern="$1" description="$2" lifecycle_log=""
    for _ in $(seq 1 20); do
      lifecycle_log="$("$ADB" logcat -d -s elisa-ui)"
      if grep -qE "$pattern" <<<"$lifecycle_log"; then
        log="$lifecycle_log"
        return 0
      fi
      sleep 0.5
    done
    echo "android: AVD lifecycle check did not observe $description" >&2
    echo "$lifecycle_log" >&2
    return 1
  }

  assert_latest_frame_orientation() {
    local orientation="$1" frame_line size width height
    frame_line="$(grep 'frame .* status=1' <<<"$log" | tail -1)"
    size="$(sed -n 's/.*frame \([0-9]*x[0-9]*\).*/\1/p' <<<"$frame_line")"
    width="${size%x*}"
    height="${size#*x}"
    if [[ "$orientation" == landscape ]]; then
      (( width > height && height == initial_width )) || {
        echo "android: expected landscape frame constrained by ${initial_width}px, got ${size}" >&2
        echo "$log" >&2
        return 1
      }
    else
      (( width < height && width == initial_width )) || {
        echo "android: expected portrait frame constrained by ${initial_width}px, got ${size}" >&2
        echo "$log" >&2
        return 1
      }
    fi
  }

  initial_size="$(sed -n 's/.*frame \([0-9]*x[0-9]*\).*/\1/p' <<<"$frame")"
  initial_width="${initial_size%x*}"
  "$ADB" logcat -c
  "$ADB" shell settings put system accelerometer_rotation 0 >/dev/null
  "$ADB" shell settings put system user_rotation 1 >/dev/null
  wait_for_lifecycle_log "frame [0-9]+x${initial_width} status=1" "landscape resize and repaint"
  assert_latest_frame_orientation landscape
  "$ADB" logcat -c
  "$ADB" shell settings put system user_rotation 0 >/dev/null
  wait_for_lifecycle_log "frame ${initial_width}x[0-9]+ status=1" "portrait resize and repaint"
  assert_latest_frame_orientation portrait

  "$ADB" logcat -c
  "$ADB" shell input keyevent 3 >/dev/null
  wait_for_lifecycle_log 'lifecycle background accepted=1' "accepted background transition"
  "$ADB" logcat -c
  "$ADB" shell am start -n "$PACKAGE/org.elisa_ui.ElisaCanvasActivity" >/dev/null
  wait_for_lifecycle_log 'lifecycle foreground accepted=1' "accepted foreground transition"
  wait_for_lifecycle_log "frame ${initial_width}x[0-9]+ status=1" "frame after foreground resume"
  assert_latest_frame_orientation portrait
  echo "android: AVD rotation and background/resume lifecycle passed"
else
  echo "android: AVD rotation/background lifecycle half skipped (requires an emulator)"
fi
