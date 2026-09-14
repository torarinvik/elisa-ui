#!/usr/bin/env bash
# Platform text boundaries translate standard UTF-8 and UTF-16. This pure
# shared-codec gate runs on the host and needs neither Windows nor Android.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${CC:-clang}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$CC" -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -fno-omit-frame-pointer -I"$ROOT/src/platform/common" \
  "$ROOT/test/utf8_utf16_codec_test.c" -o "$TMP_DIR/utf8_utf16_codec_test"
"$TMP_DIR/utf8_utf16_codec_test"
