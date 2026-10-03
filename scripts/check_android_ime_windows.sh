#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/android-ime-window-test"
mkdir -p "$OUT"
javac -d "$OUT" \
  "$ROOT/src/platform/android/java/org/elisa_ui/ElisaImeWindow.java" \
  "$ROOT/src/platform/android/java/org/elisa_ui/ElisaImeSession.java" \
  "$ROOT/src/platform/android/java/org/elisa_ui/ElisaTextMenuState.java" \
  "$ROOT/test/android_ime_traits/ElisaImeWindowTest.java" \
  "$ROOT/test/android_ime_traits/ElisaImeSessionTest.java" \
  "$ROOT/test/android_ime_traits/ElisaTextMenuStateTest.java"
java -cp "$OUT" org.elisa_ui.ElisaImeWindowTest
java -cp "$OUT" org.elisa_ui.ElisaImeSessionTest
java -cp "$OUT" org.elisa_ui.ElisaTextMenuStateTest
