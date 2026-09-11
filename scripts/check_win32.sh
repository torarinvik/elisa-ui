#!/usr/bin/env bash
# The Win32 backend: cross-compile it and prove the ABI, both directions.
#
# IT IS NEVER RUN, AND THAT IS THE POINT OF THIS HEADER. There is no Windows
# machine here and no emulator for one, so what this gate proves is exactly what
# check_uikit.sh proves for the iOS DEVICE build it also never executes: that
# the shim compiles against the real platform headers, that the Elisa backend
# compiles for the real target triple, and that every symbol each side expects
# of the other exists. A successful link is what says the two agree on an ABI.
#
# It does NOT say a window ever appeared. A green tick here means the binding is
# sound, not that the port is finished -- and saying so is the difference
# between this gate and a mapping table that listed HWND for years with nothing
# behind it.
#
# WHY THERE IS NO .exe TO RUN, precisely, because "never run" on its own is not
# a finding anyone can act on. The backend is not what blocks it: both halves
# compile for the Windows triple, and so does the Elisa runtime object. The link
# then fails on what the runtime itself needs from a POSIX host --
#
#   mmap munmap kill sigaction sysctlbyname backtrace backtrace_symbols_fd
#   va_copy va_end, plus the elisa_native_callback_* family the stage1 driver
#   supplies at its own link step and mingw's ld never sees.
#
# Those are the compiler repo's to answer, not this one's. Writing a Windows
# stand-in for them here would put a copy of the runtime's host assumptions in
# the UI project, where it would rot the first time the runtime gained a symbol
# -- which is the exact failure write_profiler_hook_fallbacks.sh exists to
# prevent. So the gate stops at the object files and says why.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
OUT="$ROOT/build/win32"
CC="x86_64-w64-mingw32-gcc"

if ! command -v "$CC" >/dev/null; then
  echo "win32: skipped (no mingw-w64; brew install mingw-w64)"
  exit 0
fi

mkdir -p "$OUT"
"$CC" -c -Wall -Wextra -Werror -municode -o "$OUT/win32_shim.o" "$ROOT/src/platform/win32/win32_shim.c"

# The Elisa half for the Windows triple. It is compiled, not linked into an
# executable: the runtime object here is macOS's, and an image is not what this
# gate is claiming.
bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -target-triple x86_64-pc-windows-gnu \
  -o "$OUT/win32_check.o" "$ROOT/src/platform/win32/win32_check.elisa"

# BOTH DIRECTIONS. Every entry the shim calls must be exported by Elisa, and
# every extern Elisa declares must be defined by the shim -- the check that
# caught a backend entry with no host stand-in earlier today.
for symbol in elisa_win32_action elisa_win32_text_action; do
  x86_64-w64-mingw32-nm "$OUT/win32_check.o" | grep -q "T $symbol" || {
    echo "win32: $symbol is called by the shim and exported by nothing" >&2; exit 1; }
done
for symbol in $(grep -o '^extern elisa_win32_[a-z_]*' "$ROOT/src/platform/win32/ui_win32_native.elisa" | awk '{print $2}'); do
  x86_64-w64-mingw32-nm "$OUT/win32_shim.o" | grep -q "T $symbol" || {
    echo "win32: Elisa declares $symbol and the shim defines nothing" >&2; exit 1; }
done

echo "win32: cross-compiled against real Windows headers; every export resolves in both directions (no image: the Elisa runtime has no Windows host yet)"
