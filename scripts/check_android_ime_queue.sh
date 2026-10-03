#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build"
"${CC:-clang}" -std=c11 -Wall -Wextra -Werror -pthread \
  "$ROOT/test/android_ime_queue_c_test.c" -o "$ROOT/build/android_ime_queue_c_test"
"$ROOT/build/android_ime_queue_c_test"
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pthread \
  "$ROOT/test/android_ime_queue_test.cpp" -o "$ROOT/build/android_ime_queue_test"
"$ROOT/build/android_ime_queue_test"
"${CC:-clang}" -std=c11 -Wall -Wextra -Werror -pthread \
  "$ROOT/test/android_ime_transport_test.c" -o "$ROOT/build/android_ime_transport_test"
"$ROOT/build/android_ime_transport_test"
