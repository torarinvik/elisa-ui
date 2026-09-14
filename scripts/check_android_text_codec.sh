#!/usr/bin/env bash
# The Android Java boundary has to translate standard UTF-8 and UTF-16 without
# an emulator. This pure codec gate runs on the host and needs no Android SDK.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${CC:-clang}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$CC" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -fno-omit-frame-pointer -I"$ROOT/src/platform/android" \
  "$ROOT/test/android_utf8_utf16_test.c" -o "$TMP_DIR/android_utf8_utf16_test"
"$TMP_DIR/android_utf8_utf16_test"
