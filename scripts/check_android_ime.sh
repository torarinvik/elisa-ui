#!/usr/bin/env bash
# IME COMPOSITION ON ANDROID, on a device, in the framework's own text field.
#
# This is the half of the Android backend that no other check could reach. The
# canvas draws its own field, so the framework owns the caret and every editing
# decision -- fine for Latin typing, where the keyboard sends finished
# characters, and not fine for most of the world. Pinyin, kana, Hangul and
# handwriting arrive as a COMPOSING run: a provisional stretch replaced again
# and again until it is committed.
#
# Until this gate that path was verified by inference. There is no CJK IME on
# the emulator to type pinyin into, and a composing run that never arrives
# paints exactly as many colours as one that does -- so the frame check could
# not catch it either, and "it should work, the Apple canvases drive the same
# API" was the whole of the evidence. That is the shape of claim this project
# has been wrong about before.
#
# WHAT IT DRIVES. The probe inside the canvas activity asks the view for an
# input connection exactly as the input method manager does, and calls it with
# the calls a pinyin keyboard makes. ElisaInputConnection is the production
# class, built by the production onCreateInputConnection, and every byte it
# forwards crosses the same JNI boundary a real IME's would. What it does not
# prove is that an IME chooses that view; onCheckIsTextEditor answers that, and
# a keyboard coming up on a real device is the evidence for it.
#
# THE SHOWCASE, because it is the only example with a text field on the painted
# backend. Reaching that field means two taps, and their coordinates are
# fractions of the frame the app reports rather than pixels of one phone. If
# they miss, this gate FAILS and says they missed -- a check that quietly
# passes when it could not reach its subject is how a whole platform stayed
# unverified here once already.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
SKIA_ROOT="${SKIA_ROOT:-}"
SKIA_OUT="${SKIA_ANDROID_OUT:-$SKIA_ROOT/out/elisa-android-arm64}"
ADB="${ADB:-$SDK/platform-tools/adb}"
PACKAGE="org.elisa_ui.showcase"

[[ -d "$SDK" ]] || { echo "android ime: skipped (no Android SDK at $SDK)"; exit 0; }
[[ -n "$NDK" && -d "$NDK" ]] || { echo "android ime: skipped (no NDK under $SDK/ndk)"; exit 0; }
[[ -n "$SKIA_ROOT" ]] || { echo "android ime: skipped (SKIA_ROOT not set)"; exit 0; }
[[ -f "$SKIA_OUT/libskia.a" ]] || { echo "android ime: skipped (no Android Skia at $SKIA_OUT)"; exit 0; }
if [[ ! -x "$ADB" ]] || ! "$ADB" devices | grep -q "	device$"; then
  echo "android ime: skipped (nothing attached; composition needs a running IME framework)"
  exit 0
fi

bash "$ROOT/scripts/build_android.sh" showcase >/dev/null
APK="$ROOT/build/android/showcase/showcase.apk"
[[ -f "$APK" ]] || { echo "android ime: the build produced no package" >&2; exit 1; }
"$ADB" install -r "$APK" >/dev/null

"$ADB" shell am force-stop "$PACKAGE" || true
for _ in $(seq 1 20); do
  [[ -z "$("$ADB" shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r')" ]] && break
  sleep 0.5
done
"$ADB" shell setprop debug.elisa.trace 1
"$ADB" logcat -c
# The extra is what arms the probe; without it this is an ordinary launch.
"$ADB" shell am start -n "$PACKAGE/org.elisa_ui.ElisaCanvasActivity" \
  --ez elisa.ime.probe true >/dev/null

# The frame trace reports the size the app actually got, which is what the two
# navigation taps are expressed against.
frame=""
for _ in $(seq 1 20); do
  sleep 1
  frame="$("$ADB" logcat -d -s elisa-ui | grep -m1 "frame " || true)"
  [[ -n "$frame" ]] && break
done
[[ -n "$frame" ]] || { echo "android ime: no frame was drawn" >&2; exit 1; }
size="$(sed -n 's/.*frame \([0-9]*x[0-9]*\).*/\1/p' <<<"$frame")"
width="${size%x*}"
height="${size#*x}"
# Per-mille of the frame, in shell arithmetic. This was an awk one-liner and
# awk spent eleven minutes waiting on stdin for a program whose braces had been
# eaten somewhere in the quoting -- a gate that hangs is worse than one that
# fails, so the arithmetic is now the shell's own and there is nothing to quote.
tap() { "$ADB" shell input tap "$(( width * $1 / 1000 ))" "$(( height * $2 / 1000 ))"; }

tap 265 618   # "Open forms" on the overview page
sleep 2
tap 499 413   # the first field on the forms page

# WAIT FOR THE PROBE TO SPEAK, do not sleep a guess. This was `sleep 4`, and on a
# freshly booted emulator four seconds was not enough: the gate read the log
# before the probe had run and failed reporting the absence of a line that was
# about to appear. The probe polls for a focused field for up to 20s, so the
# ceiling here is that plus room to finish; every terminal outcome it can reach
# (committed, no-field, no-connection) ends the wait, so a real failure is still
# prompt rather than sitting out the timeout.
for _ in $(seq 1 30); do
  log="$("$ADB" logcat -d -s elisa-ui)"
  grep -qE "ime (committed|no-field|no-connection)" <<<"$log" && break
  sleep 1
done

log="$("$ADB" logcat -d -s elisa-ui)"
"$ADB" shell am force-stop "$PACKAGE" || true

if grep -q "ime no-field" <<<"$log"; then
  echo "android ime: the navigation taps did not reach a text field, so the IME path was NOT exercised" >&2
  echo "$frame" >&2
  exit 1
fi

# THREE FACTS, and each one is a different way composition can be wrong.
#   a provisional run arrives and is marked;
#   the next one REPLACES it rather than appending -- the failure that once
#     turned "Hello" into "HeellIloo" on this very backend;
#   the commit replaces the composing run with BMP and supplementary characters
#     the key path could not have produced, and clears the mark.
expect() {
  grep -qF "$1" <<<"$log" || { echo "android ime: expected [$1]" >&2; grep "ime " <<<"$log" >&2 || true; exit 1; }
}
expect "ime composing-1 text=[ni] marked=2"
expect "ime composing-2 text=[nihao] marked=5"
expect "ime committed text=[你好👋] marked=0"

echo "android ime: a composing run arrived, was replaced, and committed as 你好👋 in the painted field"
