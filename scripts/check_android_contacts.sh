#!/usr/bin/env bash
# Native MotionEvent translation, host-runnable without an Android device.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build"
clang++ -std=c++17 -Wall -Wextra -Werror \
  "$ROOT/test/android_contact_ingress_test.cpp" -o "$ROOT/build/android_contact_ingress_test"
"$ROOT/build/android_contact_ingress_test"
clang++ -std=c++17 -Wall -Wextra -Werror \
  "$ROOT/test/android_keyboard_sync_test.cpp" -o "$ROOT/build/android_keyboard_sync_test"
"$ROOT/build/android_keyboard_sync_test"
