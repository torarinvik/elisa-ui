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
# WHY THERE IS NO .exe TO RUN. This header used to say "the Elisa runtime has no
# Windows host yet", and that was wrong -- written from a list of undefined
# symbols rather than from looking at the runtime. The runtime HAS a Windows
# host: arena.elisa selects ARENA_BACKEND_WIN32_VIRTUALALLOC, the concurrency
# runtime has CRITICAL_SECTION and CONDITION_VARIABLE branches, and perf_cores
# calls GetActiveProcessorCount. None of it was reachable, for two reasons that
# are much smaller than a port:
#
#   1. stage1's target predicates follow the HOST, not -target-triple. Its own
#      comment in codegen_static_if.elisa says so, and it exports ELISA_HOST_LINUX
#      and ELISA_HOST_X86_64 for cross-compiling -- with no Windows equivalent.
#      So a Windows triple compiles the MACOS branches, which is where mmap,
#      munmap, sysctlbyname and the pthread family in the link error came from.
#      check_gtk_linux.sh proves the mechanism: ELISA_HOST_LINUX=1 turns
#      sysctlbyname into sysconf and the Linux link goes through.
#   2. elisacore_std/debug_referee.elisa declares kill, sigaction, getpid and
#      signal with no `static if` around them. The first two have no Windows
#      equivalent, so the crash-dump path needs a guard whatever else changes.
#
# Both belong to the compiler repo. Writing Windows stand-ins here would put a
# copy of the runtime's host assumptions in the UI project, where they would rot
# the first time the runtime gained a symbol -- the exact failure
# write_profiler_hook_fallbacks.sh exists to prevent. So the gate stops at the
# object files and says what would move it.
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

echo "win32: cross-compiled against real Windows headers; every export resolves in both directions (no image: stage1 has no ELISA_HOST_WINDOWS to select the runtime's Windows branches)"
