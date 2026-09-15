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
#   1. stage1's target predicates follow the HOST, not -target-triple, and there
#      was no Windows equivalent of ELISA_HOST_LINUX -- so a Windows triple
#      compiled the MACOS branches, which is where mmap, munmap, sysctlbyname and
#      the pthread family in the link error came from. FIXED 2026-09-11:
#      ELISA_HOST_WINDOWS exists, this gate sets it, and the runtime now resolves
#      VirtualAllocEx, InitializeCriticalSection and GetActiveProcessorCount.
#      BOTH BLOCKERS ARE FIXED (2026-09-12) and this gate now links a real image.
#
#      1. The backend declined four arena bodies -- new_region_with_owner,
#         new_region_reserve, arena_region_ensure_committed, free_region -- so
#         nothing the Windows arena branch declared was declared at all.
#         The cause was NOT in the arena. `selected_static_if_lines` tracked
#         "this chain is already satisfied" in one flag across every static-if
#         row in source order, and a NESTED chain's rows are recorded between
#         an outer chain's arms. The nested `static if ELISA_TARGET_OS_LINUX:`
#         inside the mmap branch took its `static else`, set the flag, and the
#         outer `static elif ... WIN32 ...` was then skipped as already-handled.
#         macOS never noticed: the arm it needs is the chain HEAD, taken before
#         the nested rows appear. Rows now carry their chain's nesting depth and
#         satisfaction is tracked per depth (wasm-sdk-compiler 365af3c7).
#
#      2. elisacore_runtime_concurrency.elisa defines ctx_thread_create/join/
#         detach in Elisa over pthreads everywhere EXCEPT Windows, where it
#         declares them as externs for the host to supply -- and nothing did.
#         The compiler now publishes scripts/win32_thread_fallback.c alongside
#         its other stand-in families (wasm-sdk-compiler 8d61eb6e).
#
#      Reproduce the first one on any host, in one command from the compiler repo:
#        ELISA_HOST_WINDOWS=1 ELISA_HOST_X86_64=1 bash scripts/elisac_stage1.sh \
#          -O0 -target-triple x86_64-pc-windows-gnu -o /tmp/a.o elisacore_std/arena.elisa
#      It is the SOURCE, not the target: force ARENA_BACKEND to the win32 value and
#      compile for darwin and the same four decline.
#
#      TECHNIQUE, because it cost most of a day. `static error(...)` is not valid
#      at top level: a probe planting one there dies as a parse error, prints
#      nothing your grep matches, and reads exactly like "that branch was skipped".
#      Three conclusions in that investigation were artifacts of probes with no
#      control -- including "there is no row for the win32 arm", which was false
#      and came from guessing line numbers. Probe with marker functions read back
#      through llvm-nm, or with record_declined_function (its names land in the
#      "backend declined" warning, so it needs no print plumbing), and ALWAYS
#      plant a positive control in a branch you know is taken.
#
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
OUT="$ROOT/build/win32"
CC="x86_64-w64-mingw32-gcc"

if ! command -v "$CC" >/dev/null; then
  echo "win32: skipped (no mingw-w64; brew install mingw-w64)"
  exit 0
fi

mkdir -p "$OUT"
"$CC" -c -Wall -Wextra -Werror -municode -o "$OUT/win32_shim.o" "$ROOT/src/platform/win32/win32_shim.c"

# The Elisa half for the Windows triple.
# ELISA_HOST_WINDOWS is what makes -target-triple mean anything to the std's
# `static if ELISA_TARGET_OS_*` rows; without it a Windows triple compiles the
# macOS branches. It exists as of 2026-09-11 (see the header above).
ELISA_HOST_WINDOWS=1 ELISA_HOST_X86_64=1 \
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

# A transparent update clears the framework-owned colour record, and an
# ink-only update releases any no-longer-reachable fill brush. Keep this guard
# beside the cross-compiled seam so a future refactor cannot reintroduce a GDI
# leak that only appears after reconciliation.
grep -q 'forget_color_slot(control);' "$ROOT/src/platform/win32/win32_shim.c" || {
  echo "win32: color clearing does not release stale records" >&2; exit 1; }
grep -q 'colored\[slot\]\.brush = NULL;' "$ROOT/src/platform/win32/win32_shim.c" || {
  echo "win32: ink-only color updates do not release stale brushes" >&2; exit 1; }

# AND AN IMAGE. Objects that each resolve say nothing about whether the whole
# thing links; this gate stopped at objects for months while the runtime's
# Windows arena branch was declined by the backend and its thread entries had
# no stand-in. Both are fixed (wasm-sdk-compiler 365af3c7 and 8d61eb6e), so
# link the real thing and refuse to pass on anything less than a PE32+ binary.
ELISA_HOST_WINDOWS=1 ELISA_HOST_X86_64=1 \
  bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -target-triple x86_64-pc-windows-gnu \
    -o "$OUT/elisacore_runtime_win.o" "$STAGE1/elisacore_std/elisacore_runtime.elisa"

# The three stand-in families the COMPILER publishes for a downstream link. They
# live there, not here: a copy of the runtime's host assumptions in this project
# would rot the first time the runtime gained a symbol.
"$CC" -c -o "$OUT/win32_threads.o" "$STAGE1/scripts/win32_thread_fallback.c"
bash "$STAGE1/scripts/write_profiler_hook_fallbacks.sh" > "$OUT/profiler_fallbacks.c"
"$CC" -c -o "$OUT/profiler_fallbacks.o" "$OUT/profiler_fallbacks.c"
# -fno-builtin: this one defines va_copy/va_end over clang builtins.
"$CC" -c -fno-builtin -o "$OUT/pymodule_fallback.o" "$STAGE1/scripts/pymodule_runtime_fallback.c"

"$CC" -o "$OUT/elisa_win32.exe" \
  "$OUT/win32_check.o" "$OUT/win32_shim.o" "$OUT/elisacore_runtime_win.o" \
  "$OUT/win32_threads.o" "$OUT/profiler_fallbacks.o" "$OUT/pymodule_fallback.o" \
  -lgdi32 -luser32 -lkernel32 -lcomctl32

file "$OUT/elisa_win32.exe" | grep -q "PE32+ executable" || {
  echo "win32: linked something, but it is not a PE32+ image" >&2; exit 1; }

echo "win32: a PE32+ image links from real Windows headers -- every export resolves in both directions, and the Elisa runtime cross-compiles with zero declines"
