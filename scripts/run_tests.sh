#!/usr/bin/env bash
# Build and run the elisa-ui test programs. These need no window or backend:
# each links against the core plus the layer under test and reports through its
# exit status.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE1="${ELISA_UI_STAGE1:-$ROOT/../wasm-sdk-compiler}"
RUNTIME="$STAGE1/build/runtime/elisacore_runtime.o"
SDL_LIB="${ELISA_UI_SDL_LIB:-/opt/homebrew/lib}"
require_real_skia="${ELISA_UI_REQUIRE_REAL_SKIA:-1}"

case "$require_real_skia" in
  0|1) ;;
  *)
    echo "ELISA_UI_REQUIRE_REAL_SKIA must be 0 or 1 (got $require_real_skia)" >&2
    exit 2
    ;;
esac

[[ -x "$STAGE1/bin/elisac-stage1" ]] || { echo "no stage1 product at $STAGE1/bin/elisac-stage1" >&2; exit 2; }
[[ -f "$RUNTIME" ]] || { echo "no runtime object at $RUNTIME" >&2; exit 2; }
bash "$ROOT/scripts/check_toolchain.sh"

mkdir -p "$ROOT/build"
status=0

SKIA_TEST_SHIM="$ROOT/build/skia_painter_shim.o"
clang -c -Wall -Wextra -Werror -o "$SKIA_TEST_SHIM" "$ROOT/test/skia_painter_shim.c"
# The UIKit tests exercise the whole backend below the Objective-C shim, so
# they link C stand-ins for the entry points that shim would provide.
UIKIT_TEST_STUBS="$ROOT/build/uikit_host_stubs.o"
clang -c -Wall -Wextra -Werror -o "$UIKIT_TEST_STUBS" "$ROOT/test/uikit_host_stubs.c"
# The native-controls backend has its own, disjoint shim boundary.
UIKIT_CONTROLS_TEST_STUBS="$ROOT/build/uikit_controls_host_stubs.o"
clang -c -Wall -Wextra -Werror -o "$UIKIT_CONTROLS_TEST_STUBS" "$ROOT/test/uikit_controls_host_stubs.c"

# The real custom renderer is a required gate by default. Run it before the
# longer portable/native matrix so a missing pinned SDK fails immediately and
# cannot be mistaken for a complete test run.
if [[ "$require_real_skia" == "1" ]]; then
  if ! bash "$ROOT/scripts/check_skia.sh"; then
    echo "FAIL required skia renderer" >&2
    echo "run ELISA_UI_REQUIRE_REAL_SKIA=0 only for a non-passing compiler-only edit loop" >&2
    exit 2
  fi
fi

if ! bash "$ROOT/scripts/check_source_sizes.sh"; then
  echo "FAIL source sizes"
  status=1
fi

if ! bash "$ROOT/scripts/check_global_names.sh"; then
  echo "FAIL global names"
  status=1
fi

# The laws in src/ are only worth the compiler's willingness to complain about
# them, and a refinement that stops being checked keeps compiling silently. This
# compiles one fixture that must be reported and one that must not.
if ! bash "$ROOT/scripts/check_refinements.sh"; then
  echo "FAIL refinements"
  status=1
fi

# Execute the pinned Unicode GraphemeBreakTest corpus through the same
# UiText::next_grapheme used by editors and line layout. The small curated
# regression fixture remains in the per-test loop; this data-driven gate is
# the conformance evidence and must not be reduced to helper combinations.
if ! bash "$ROOT/scripts/check_unicode_conformance.sh"; then
  echo "FAIL unicode conformance"
  status=1
fi

# Keep a measured retained-tree workload in the required suite. This is a
# safety/performance gate for application-scale layout, paint, text and editing
# work; it never opens a native window and reports its own timing/RSS evidence.
if ! bash "$ROOT/scripts/check_performance.sh"; then
  echo "FAIL performance benchmark"
  status=1
fi

# The C boundary is checked by building a real C program against the library --
# the header and the Elisa side are two hand-written descriptions of one ABI, and
# nothing in the Elisa suite sees the header.
if ! bash "$ROOT/scripts/check_capi.sh"; then
  echo "FAIL capi"
  status=1
fi

# The same C boundary has a Rust face; the wrapper enforces borrowed-text and
# opaque-handle lifetimes in the type system. Skips itself without rustc.
if ! bash "$ROOT/scripts/check_rust.sh"; then
  echo "FAIL rust"
  status=1
fi

# The AppKit backend builds REAL NSViews, so it needs Cocoa and its own link
# line. Skips itself off macOS. It never shows a window.
if ! bash "$ROOT/scripts/check_appkit.sh"; then
  echo "FAIL appkit"
  status=1
fi

# The custom AppKit renderer is a separate architecture from native controls:
# validate its Elisa/Objective-C callback boundary and packaged .app as well.
if ! bash "$ROOT/scripts/check_appkit_canvas.sh"; then
  echo "FAIL appkit canvas"
  status=1
fi

# The UIKit backend has no window to open and no simulator to boot: its shim is
# type-checked against the real iOS SDK and everything below it is built and run
# here, including one real off-screen frame.
if ! bash "$ROOT/scripts/check_uikit.sh"; then
  echo "FAIL uikit"
  status=1
fi

# ...and then actually run them. This boots a simulator, so it skips itself
# when no iOS runtime is installed rather than failing a machine that has none.
if ! bash "$ROOT/scripts/check_uikit_simulator.sh"; then
  echo "FAIL uikit simulator"
  status=1
fi

# ...and a real touch. simctl cannot inject one, so this drives XCUIApplication
# through the simulator's own HID pipeline. Skips itself like the gate above.
if ! bash "$ROOT/scripts/check_uikit_touch.sh"; then
  echo "FAIL uikit touch"
  status=1
fi

# WIN32 IS THE LAST COLUMN. It is cross-compiled and never run, which is the
# same evidence the iOS device build gives, and the gate's own output says so.
if ! bash "$ROOT/scripts/check_win32.sh"; then
  echo "FAIL win32"
  status=1
fi

# GTK IS THE LINUX HALF OF THE NATIVE STORY, and it is gated the same way: it
# skips itself when gtk4 is not installed, and the fixture skips again when
# there is no display, so a machine without either is not failed for it.
# The framework itself on Linux, not just a backend: the portable corpus
# cross-compiled, linked and run inside a Linux machine. It skips without one.
# This is the gate that can tell whether "multi-platform" describes the layout,
# text, state and event machinery or only the backends bolted to them.
if ! bash "$ROOT/scripts/check_core_linux.sh"; then
  echo "FAIL core linux"
  status=1
fi

# ...and the same fixture on Linux, which is the platform the GTK backend is
# for. It skips without an OrbStack machine; check_gtk.sh above still runs the
# macOS build, because a binding that compiles in two places is worth more than
# one that compiles in one.
if ! bash "$ROOT/scripts/check_gtk_linux.sh"; then
  echo "FAIL gtk linux"
  status=1
fi

if ! bash "$ROOT/scripts/check_gtk.sh"; then
  echo "FAIL gtk"
  status=1
fi

# ANDROID IS A PLATFORM THIS FRAMEWORK CLAIMS, SO THE SUITE HAS TO ASK ABOUT IT.
# Both Android backends -- the Skia canvas and the android.widget controls --
# were outside this file entirely: the gate existed and nothing ran it, so every
# green suite here was green about five platforms while saying nothing at all
# about the sixth. It skips itself when the SDK, the NDK, an emulator or the
# Android Skia build is missing, which is the same courtesy the iOS device gates
# get -- but a machine that has all four now has to pass.
#
# SKIA_ROOT has to reach it or it skips on a machine that could have run it.
# That is how it went unnoticed: the skip line reads like a fact about the
# machine rather than about the environment it was handed.
if ! SKIA_ROOT="${SKIA_ROOT:-}" bash "$ROOT/scripts/check_android.sh"; then
  echo "FAIL android"
  status=1
fi

# The hosted target, which was outside this suite entirely: check_wapp.sh
# existed, was documented as the WasmBrowser gate, and nothing invoked it -- the
# same way check_android.sh sat unrun. It skips when the sibling checkout or its
# CLI is missing, and it builds the package before inspecting it.
if ! bash "$ROOT/scripts/check_wapp.sh"; then
  echo "FAIL wapp"
  status=1
fi

# Composition is a separate gate because it needs a separate thing: a device
# with a live IME framework, and the one example that has a text field on the
# painted backend. It skips itself without those, and it is the only check in
# this suite that can tell a composing run that arrived from one that did not.
if ! SKIA_ROOT="${SKIA_ROOT:-}" bash "$ROOT/scripts/check_android_ime.sh"; then
  echo "FAIL android ime"
  status=1
fi

# The AppKit/Skia compositor extends the required CPU-raster gate when it is
# available on macOS; its fixture remains headless and never foregrounds a UI.
if [[ "$require_real_skia" == "1" ]]; then
  if ! bash "$ROOT/scripts/check_appkit_skia.sh"; then
    echo "FAIL appkit skia"
    status=1
  fi
elif [[ -n "${SKIA_ROOT:-}" ]]; then
  if ! ELISA_UI_REQUIRE_REAL_SKIA=0 bash "$ROOT/scripts/check_skia.sh"; then
    echo "FAIL skia compiler check"
    status=1
  fi
fi

for source in "$ROOT"/test/*_test.elisa; do
  name="$(basename "$source" .elisa)"
  # The real Skia fixtures are library entry points driven by their C++ hosts;
  # the dedicated renderer gate owns their compile/link/run lifecycle.
  if [[ "$name" == "skia_offscreen_test" || "$name" == "showcase_skia_test" || "$name" == "showcase_app_skia_test" || "$name" == "storefront_skia_test" || "$name" == "appkit_skia_host_test" ]]; then
    continue
  fi
  bash "$STAGE1/scripts/elisac_stage1.sh" -O0 -o "$ROOT/build/$name.o" "$source"
  # Link SDL for tests that exercise the native backend; the others simply
  # do not reference these symbols.
  link_inputs=("$RUNTIME")
  if [[ "$name" == "skia_painter_test" ]]; then
    link_inputs=("$SKIA_TEST_SHIM" "$RUNTIME")
  fi
  if [[ "$name" == "uikit_controls_test" ]]; then
    link_inputs=("$UIKIT_CONTROLS_TEST_STUBS" "$RUNTIME")
  elif [[ "$name" == uikit_* ]]; then
    link_inputs=("$UIKIT_TEST_STUBS" "$RUNTIME")
  fi
  if [[ "$name" == uikit_* && "$(uname -s)" == "Darwin" ]]; then
    clang -Wl,-dead_strip -o "$ROOT/build/$name" "$ROOT/build/$name.o" "${link_inputs[@]}" -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework ImageIO
  elif [[ "$name" == appkit_canvas_* && "$(uname -s)" == "Darwin" ]]; then
    clang -Wl,-dead_strip -o "$ROOT/build/$name" "$ROOT/build/$name.o" "${link_inputs[@]}" -L"$SDL_LIB" -lSDL3 -lSDL3_ttf -Wl,-rpath,"$SDL_LIB" -framework CoreFoundation -framework AppKit
  else
    clang -Wl,-dead_strip -o "$ROOT/build/$name" "$ROOT/build/$name.o" "${link_inputs[@]}" -L"$SDL_LIB" -lSDL3 -lSDL3_ttf -Wl,-rpath,"$SDL_LIB"
  fi
  if "$ROOT/build/$name"; then
    echo "PASS $name"
  else
    echo "FAIL $name" >&2
    status=1
  fi
done

exit "$status"
