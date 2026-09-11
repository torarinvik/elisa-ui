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
#      What still blocks an image is that the Windows arena branch had never been
#      compiled by stage1 and the backend declines four of its bodies.
#
#      REPRODUCE IT IN ONE COMMAND, from the compiler repo (2026-09-11):
#        ELISA_HOST_WINDOWS=1 ELISA_HOST_X86_64=1 bash scripts/elisac_stage1.sh \
#          -O0 -target-triple x86_64-pc-windows-gnu -o /tmp/a.o elisacore_std/arena.elisa
#      It exits 0 and warns: "backend declined 4 function body(ies); the object does
#      not define: new_region_with_owner, new_region_reserve,
#      arena_region_ensure_committed, free_region (call expression)". The same source
#      compiled for x86_64-unknown-linux-gnu (ELISA_HOST_LINUX=1) or x86_64-apple-darwin
#      declines NOTHING, so it is the Windows branch, not the file.
#
#      Localized: the VirtualAllocEx/VirtualFreeEx CALLS. Swapping just the
#      VirtualAllocEx in new_region_with_owner for malloc() drops the count 4 -> 3,
#      leaving the other three -- those are exactly the four functions that call the
#      two Win32 externs.
#
#      NOT the Windows target -- the win32 SOURCE. Force ARENA_BACKEND to the win32
#      value and compile for x86_64-apple-darwin: the same four decline. So the whole
#      target/host-predicate machinery is off the hook.
#
#      Branch selection is CORRECT. Put a marker `def` in each branch of both static
#      chains and read the object with llvm-nm: a Windows build keeps exactly
#      marker_sel_windows and marker_decl_win32; a macOS build keeps marker_decl_mmap.
#      The win32 block's own code IS emitted -- and yet its `def`, its `extern` AND its
#      `const` are all invisible to callers, including a caller written at top level
#      outside every static if. The mirror on macOS (a top-level call of MAP_FAILED,
#      declared only inside the mmap block) resolves fine, so the failure is specific
#      to the Windows configuration rather than to static blocks in general.
#
#      Ruled OUT by experiment, so the next session need not re-derive them: a nested
#      zero-arg call argument (GetCurrentProcess()); `assert not <call>`; the multi-line
#      extern spelling; untyped const arguments; a `|` of consts; declaring an extern
#      inside a static if/elif at all; the branch's POSITION (reordering the chain so
#      win32 comes first changes nothing); the condition's foldability (rewriting it to
#      the round-0-foldable ELISA_TARGET_OS_WINDOWS changes nothing); hoisting the
#      declarations to top level (only changes the reported reason to "expression");
#      hoisting collections.elisai's duplicate win32 block out of its own static chain;
#      and registering the settling round's consts before `break if settled` in
#      Backend::select_module_declarations (tried as a compiler patch -- no effect).
#
#      INSTRUMENTED, and this is the sharpest fact so far: declare_extern is NEVER
#      CALLED for the win32 externs. Planting a marker at the entry of
#      Backend::declare_extern (src/backend/codegen_declare_extern.elisa) that fires
#      for "GetCurrentProcess", alongside a positive control that fires for "malloc",
#      a Windows build reports the control twice (entered + registered) and the test
#      not at all. So the externs never reach the declare pass, which walks the
#      FLATTENED `top` list (src/backend/codegen_debug.elisa) -- while a marker `def`
#      planted in the very same block IS emitted into the object.
#
#      Probed `top` itself, same way, with the malloc control still firing: NEITHER the
#      win32 externs NOR the block's own `def` (win_commit_round_up) are in it. The block
#      is missing from the flattened declaration list entirely. Rebuilding `top` from the
#      selection that codegen_module.elisa recomputes AFTER its rounds (tried as a patch,
#      rebuilt, measured) does not help either -- so that FINAL selection does not contain
#      the block's line, which means `fold_const_expr` never folds
#      `ARENA_BACKEND == ARENA_BACKEND_WIN32_VIRTUALALLOC` at all, while it does fold the
#      LINUX_MMAP arm of the same chain on a macOS build.
#
#      That is the lead to pull next, and note that ARENA_BACKEND is declared TWICE in the
#      std -- arena.elisa and collections.elisai each carry their own copy of the selection
#      chain, and collections.elisai additionally defines a local `const
#      ELISA_TARGET_OS_WASM: bool = false`. register_target_consts refuses to re-register a
#      name that already exists (`continue if const_index_of(...) >= 0`), so which file's
#      ARENA_BACKEND wins, and with what value, is worth measuring before anything else.
#
#      Unexplained alongside it, and worth reconciling: a marker `def` planted in that same
#      win32 block IS emitted into the object (llvm-nm, with marker_decl_mmap absent on the
#      same build as the control). Declaration and emission are disagreeing about the block.
#
#      Note when instrumenting: two functions in codegen_declare_extern.elisa open with
#      the identical line `if declaration is Decl.Extern(...)`, so a naive
#      first-occurrence patch lands in register_one_opaque_extern instead. Anchor after
#      `def declare_extern(`. And the seed refuses to run concurrently with another
#      seed on the host, so a patch-seed-probe loop must serialize.
#
#      TECHNIQUE, because it cost an afternoon: `static error(...)` is NOT valid at top
#      level. A probe that plants one there dies as a parse error, prints nothing your
#      grep matches, and reads exactly like "the branch was skipped". Probe with marker
#      functions and llvm-nm instead, and always plant a POSITIVE CONTROL in a branch
#      you know is taken -- three conclusions in this investigation were artifacts that
#      only a control exposed.
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

echo "win32: cross-compiled against real Windows headers; every export resolves in both directions (no image: the runtime's Windows arena branch is declined by the backend)"
