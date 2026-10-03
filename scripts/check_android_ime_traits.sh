#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
PLATFORM_JAR="$(ls "$SDK"/platforms/*/android.jar 2>/dev/null | sort -V | tail -1 || true)"
[[ -f "$PLATFORM_JAR" ]] || { echo "android IME traits: skipped (no Android SDK)"; exit 0; }
OUT="$ROOT/build/android-ime-traits"
mkdir -p "$OUT"
javac -classpath "$PLATFORM_JAR" -d "$OUT" \
  "$ROOT/src/platform/android/java/org/elisa_ui/ElisaImeTraits.java" \
  "$ROOT/test/android_ime_traits/ElisaImeTraitsTest.java"
java -cp "$OUT:$PLATFORM_JAR" org.elisa_ui.ElisaImeTraitsTest
