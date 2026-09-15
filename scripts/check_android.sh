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
OUT="$ROOT/build/android/$EXAMPLE"
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
             elisa_android_touch elisa_android_scroll elisa_android_frame_delay \
             elisa_android_lifecycle elisa_android_key elisa_android_text \
             elisa_android_wants_keyboard; do
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

# --- 2. A device, if one is attached ------------------------------------
ADB="${ADB:-$SDK/platform-tools/adb}"
if [[ ! -x "$ADB" ]] || ! "$ADB" devices | grep -q "	device$"; then
  echo "android: skipped the device half (nothing attached)"
  exit 0
fi

PACKAGE="org.elisa_ui.$EXAMPLE"
"$ADB" install -r "$APK" >/dev/null
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
  "$ADB" shell am force-stop "$PACKAGE" || true
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
