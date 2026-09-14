#!/usr/bin/env bash
# The portable test corpus, compiled for Linux and run on Linux.
#
# WHAT THIS IS FOR. Every other gate here proves one backend. This one asks a
# different question: is the FRAMEWORK portable, or only its GTK binding? The
# answer had never been checked -- the whole corpus has only ever run on macOS,
# so "multi-platform" rested on the platform-specific backends compiling, not on
# the layout, text, state, identity and event machinery under them running
# anywhere else.
#
# It runs the same tests scripts/run_tests.sh runs, minus the ones that link
# Apple frameworks (appkit_canvas_*, uikit_*) and the Skia host fixtures the
# renderer gate owns. On this machine that is 66 of the 73.
#
# IT FOUND SOMETHING IMMEDIATELY, which is the argument for having it: the SDL3
# backend -- the one Linux and Windows paint through -- had a single macOS font
# path as its default, so no font opened on Linux at all. Widths fell to zero
# while ascent and line height fell back to the requested point size, and three
# of the SDL text fixture's own assertions passed anyway on a machine with no
# font. Metrics invented rather than asked of the platform, in the backend
# least likely to be looked at from a Mac.
#
# See check_gtk_linux.sh for why ELISA_HOST_LINUX is needed to cross-compile:
# stage1's target predicates follow the host, not -target-triple.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../Elisa-compiler}"
OUT="$ROOT/build/core-linux"

command -v orb >/dev/null || { echo "core linux: skipped (no orb; OrbStack provides the Linux machine)"; exit 0; }
MACHINE="${ELISA_UI_ORB_MACHINE:-$(orb list 2>/dev/null | awk '$2 == "running" {print $1; exit}')}"
[[ -n "$MACHINE" ]] || { echo "core linux: skipped (no running OrbStack machine; orb start <name>)"; exit 0; }

probe="$(orb -m "$MACHINE" bash -c 'uname -m; command -v clang >/dev/null && echo clang; pkg-config --exists sdl3 && echo sdl3; pkg-config --exists sdl3-ttf && echo sdl3ttf' 2>/dev/null || true)"
ARCH="$(head -1 <<<"$probe")"
[[ -n "$ARCH" ]] || { echo "core linux: skipped (machine '$MACHINE' did not answer; orb list)"; exit 0; }
for tool in clang sdl3 sdl3ttf; do
  grep -qx "$tool" <<<"$probe" || {
    echo "core linux: skipped ($MACHINE has no $tool; apt install clang pkg-config libsdl3-dev libsdl3-ttf-dev)"
    exit 0; }
done

case "$ARCH" in
  aarch64) TRIPLE="aarch64-unknown-linux-gnu"; HOST_ARCH_FLAG="" ;;
  x86_64)  TRIPLE="x86_64-unknown-linux-gnu";  HOST_ARCH_FLAG="ELISA_HOST_X86_64=1" ;;
  *) echo "core linux: skipped (unsupported machine architecture $ARCH)"; exit 0 ;;
esac

rm -rf "$OUT"
mkdir -p "$OUT"
bash "$STAGE1/scripts/write_profiler_hook_fallbacks.sh" >"$OUT/profiler_fallbacks.c"
cp "$STAGE1/scripts/pymodule_runtime_fallback.c" "$OUT/host_fallbacks.c"
cp "$ROOT/test/skia_painter_shim.c" "$ROOT/include/elisa_skia.h" "$OUT/"

compile() {
  env ELISA_HOST_LINUX=1 ${HOST_ARCH_FLAG:+"$HOST_ARCH_FLAG"} \
    bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -target-triple "$TRIPLE" -o "$2" "$1"
}
compile "$STAGE1/elisacore_std/native_runtime_support.elisa" "$OUT/runtime.o"

expected=0
for source in "$ROOT"/test/*_test.elisa; do
  name="$(basename "$source" .elisa)"
  case "$name" in
    # The Skia host fixtures belong to the renderer gate, exactly as in
    # run_tests.sh; the Apple ones link frameworks that do not exist here.
    skia_offscreen_test|showcase_skia_test|showcase_app_skia_test|storefront_skia_test|appkit_skia_host_test) continue ;;
    appkit_canvas_*|uikit_*) continue ;;
  esac
  compile "$source" "$OUT/$name.o"
  expected=$((expected + 1))
done

GUEST="/mnt/mac$OUT"
orb -m "$MACHINE" bash -c "
set -u
work=\$(mktemp -d); mkdir -p \"\$work/test\" \"\$work/include\"
trap 'rm -rf \"\$work\"' EXIT
cp '$GUEST'/*.o '$GUEST'/profiler_fallbacks.c '$GUEST'/host_fallbacks.c '$GUEST'/skia_painter_shim.c \"\$work/test/\"
cp '$GUEST'/elisa_skia.h \"\$work/include/\"
cd \"\$work/test\"
clang -c -o profiler_fallbacks.o profiler_fallbacks.c
# -fno-builtin: the compiler's fallback file defines va_copy and va_end over
# what a current clang treats as builtins.
clang -fno-builtin -c -o host_fallbacks.o host_fallbacks.c
clang -c -o skia_painter_shim.o skia_painter_shim.c
pass=0
for obj in *_test.o; do
  name=\${obj%.o}
  shim=''
  [ \"\$name\" = skia_painter_test ] && shim=skia_painter_shim.o
  if ! clang -o \"\$name\" \"\$obj\" \$shim runtime.o profiler_fallbacks.o host_fallbacks.o \\
       \$(pkg-config --libs sdl3 sdl3-ttf) -lpthread -lm >/tmp/elisa-link.err 2>&1; then
    echo \"LINKFAIL \$name\"; head -5 /tmp/elisa-link.err; continue
  fi
  if ./\"\$name\" >/tmp/elisa-run.out 2>&1; then pass=\$((pass+1)); else echo \"FAIL \$name\"; cat /tmp/elisa-run.out; fi
done
echo \"PASSED=\$pass\"
" >"$OUT/run.log" 2>&1 || { echo "core linux: the run failed" >&2; cat "$OUT/run.log" >&2; exit 1; }

if grep -qE "^(FAIL|LINKFAIL) " "$OUT/run.log"; then
  echo "core linux: tests failed on Linux" >&2
  grep -A6 -E "^(FAIL|LINKFAIL) " "$OUT/run.log" >&2
  exit 1
fi
passed="$(sed -n 's/^PASSED=//p' "$OUT/run.log")"
# A gate that reports a pass count is only worth the count being the one it set
# out to run. Silence after a truncated loop is what this compares against.
[[ "$passed" == "$expected" ]] || {
  echo "core linux: compiled $expected tests but only $passed ran" >&2; cat "$OUT/run.log" >&2; exit 1; }

echo "core linux: $passed of the portable corpus compiled for $ARCH Linux, linked and passed there"
