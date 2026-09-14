#!/usr/bin/env bash
# The GTK backend, on Linux, where it is actually meant to run.
#
# WHAT THIS CLOSES. check_gtk.sh builds and runs the same fixture on macOS,
# where GTK is a supported target, and its header is careful to say that this is
# not the same as having run on Linux: a GTK widget does not know which platform
# it is on, but the windowing below it does. This gate removes the caveat rather
# than restating it. Same fixture, same assertions, compiled for aarch64 or
# x86_64 Linux, linked and run inside an OrbStack Linux machine against a real
# X server.
#
# A REAL DISPLAY, NOT A SKIP. The fixture answers "skipped (no display)" when
# gtk_init_check fails, which is the right courtesy in a gate and the wrong
# outcome here -- a skip under Xvfb means the harness broke, not that the
# machine is headless, so this gate fails on it.
#
# CROSS-COMPILED, AND WHY IT NEEDS ELISA_HOST_LINUX. stage1's target predicates
# (ELISA_TARGET_OS_MACOS and friends) follow the HOST, not -target-triple; the
# compiler's own comment in codegen_static_if.elisa says so, and exports
# ELISA_HOST_LINUX for exactly this. Without it the runtime compiles its macOS
# branch for a Linux triple and the link fails on sysctlbyname -- a BSD call
# whose Linux counterpart, sysconf(_SC_NPROCESSORS_ONLN), is already written in
# elisacore_runtime_concurrency.elisa and simply was not selected.
#
# The two fallback sources come from the compiler repo, not from here. Writing
# Elisa's runtime ABI into this project is the mistake the Win32 gate declines
# to make; sourcing what the compiler already publishes for downstream links is
# the pattern write_profiler_hook_fallbacks.sh exists for.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
OUT="$ROOT/build/gtk-linux"

command -v orb >/dev/null || { echo "gtk linux: skipped (no orb; OrbStack provides the Linux machine)"; exit 0; }
MACHINE="${ELISA_UI_ORB_MACHINE:-$(orb list 2>/dev/null | awk '$2 == "running" {print $1; exit}')}"
[[ -n "$MACHINE" ]] || { echo "gtk linux: skipped (no running OrbStack machine; orb start <name>)"; exit 0; }

# What the machine has, asked of the machine. The `uname -m` line is first so an
# empty answer distinguishes "the machine did not respond" from "the machine is
# missing a tool" -- a skip line that names the wrong reason is worse than no
# skip line, because someone acts on it.
probe="$(orb -m "$MACHINE" bash -c 'uname -m; command -v clang >/dev/null && echo clang; command -v xvfb-run >/dev/null && echo xvfb; pkg-config --exists gtk4 && echo gtk4' 2>/dev/null || true)"
ARCH="$(head -1 <<<"$probe")"
[[ -n "$ARCH" ]] || { echo "gtk linux: skipped (machine '$MACHINE' did not answer; orb list)"; exit 0; }
for tool in clang xvfb gtk4; do
  grep -qx "$tool" <<<"$probe" || {
    echo "gtk linux: skipped ($MACHINE has no $tool; apt install libgtk-4-dev clang pkg-config xvfb)"
    exit 0; }
done

case "$ARCH" in
  aarch64) TRIPLE="aarch64-unknown-linux-gnu"; HOST_ARCH_FLAG="" ;;
  x86_64)  TRIPLE="x86_64-unknown-linux-gnu";  HOST_ARCH_FLAG="ELISA_HOST_X86_64=1" ;;
  *) echo "gtk linux: skipped (unsupported machine architecture $ARCH)"; exit 0 ;;
esac

mkdir -p "$OUT"
bash "$STAGE1/scripts/write_profiler_hook_fallbacks.sh" >"$OUT/profiler_fallbacks.c"
cp "$STAGE1/scripts/pymodule_runtime_fallback.c" "$OUT/host_fallbacks.c"
cp "$ROOT/src/platform/gtk/gtk_shim.c" "$OUT/gtk_shim.c"

for unit in "$ROOT/src/platform/gtk/gtk_check.elisa:gtk_check" \
            "$ROOT/src/platform/gtk/gtk_style_lifecycle_check.elisa:gtk_style_lifecycle_check" \
            "$STAGE1/elisacore_std/native_runtime_support.elisa:runtime"; do
  env ELISA_HOST_LINUX=1 ${HOST_ARCH_FLAG:+"$HOST_ARCH_FLAG"} \
    bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -target-triple "$TRIPLE" \
      -o "$OUT/${unit##*:}.o" "${unit%%:*}"
done

# The Mac filesystem is mounted inside the machine, so the objects cross without
# a copy step; only the build and the run happen over there.
GUEST="/mnt/mac$OUT"
orb -m "$MACHINE" bash -c "
set -e
work=\$(mktemp -d)
trap 'rm -rf \"\$work\"' EXIT
cd \"\$work\"
cp '$GUEST'/gtk_check.o '$GUEST'/gtk_style_lifecycle_check.o '$GUEST'/runtime.o '$GUEST'/gtk_shim.c '$GUEST'/profiler_fallbacks.c '$GUEST'/host_fallbacks.c .
clang -c -Wall -Wextra -Werror \$(pkg-config --cflags gtk4) -o gtk_shim.o gtk_shim.c
clang -c -o profiler_fallbacks.o profiler_fallbacks.c
# -fno-builtin: this file defines va_copy and va_end, which a current clang
# refuses to let a program redeclare over its builtins.
clang -fno-builtin -c -o host_fallbacks.o host_fallbacks.c
clang -o gtk_check gtk_check.o gtk_shim.o runtime.o profiler_fallbacks.o host_fallbacks.o \$(pkg-config --libs gtk4) -lpthread -lm
clang -o gtk_style_lifecycle_check gtk_style_lifecycle_check.o gtk_shim.o runtime.o profiler_fallbacks.o host_fallbacks.o \$(pkg-config --libs gtk4) -lpthread -lm
xvfb-run -a ./gtk_check
xvfb-run -a ./gtk_style_lifecycle_check
" >"$OUT/run.log" 2>"$OUT/run.err" || { echo "gtk linux: the fixture failed" >&2; cat "$OUT/run.log" "$OUT/run.err" >&2; exit 1; }

if grep -q "skipped (no display)" "$OUT/run.log"; then
  echo "gtk linux: the fixture found no display under Xvfb, so nothing was asserted" >&2
  exit 1
fi
grep -q "gtk: all checks passed" "$OUT/run.log" || {
  echo "gtk linux: the fixture did not pass" >&2; cat "$OUT/run.log" >&2; exit 1; }
grep -q "gtk style lifetime: all checks passed (256 lifetimes, peak 128)" "$OUT/run.log" || {
  echo "gtk linux: the headless style-lifetime fixture did not pass" >&2; cat "$OUT/run.log" >&2; exit 1; }

echo "gtk linux: same fixture, $ARCH Linux, real X server -- every type, state, shape and colour asserted"
