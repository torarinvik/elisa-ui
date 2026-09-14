# Renderer verification status

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


## Latest verification: 2026-09-14

The pinned Skia checkout and CPU-raster archive are now built locally. From a
fresh checkout, provision them without opening a window:

```
export SKIA_ROOT=/path/to/elisa-skia
export SKIA_OUT="$SKIA_ROOT/out/elisa"
bash scripts/build_skia.sh
```

The required CPU-raster gate was run against compiler revision
`9791a8e1cd924bb03e43cb46da2d3530b4c9fbb0` and Skia revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`. The archive SHA-256 is
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`.

```sh
PATH="/path/to/depot_tools:$PATH" \
ELISA_STAGE1_NO_SEMANTIC_GATE=1 \
ELISA_UI_STAGE1=../wasm-sdk-compiler \
SKIA_ROOT=/path/to/elisa-skia \
SKIA_OUT="$SKIA_ROOT/out/elisa" \
bash scripts/check_skia.sh
```

`ELISA_UI_REQUIRE_REAL_SKIA` defaults to `1`; `check_skia.sh` therefore
requires and verifies the real pinned archive, renders pixels, checks stable
fresh-process replay digests, and writes the five showcase pages plus focus,
high-contrast, light, RTL, dialog, 2x, hover, and pressed images under
`build/`. The command above uses `ELISA_STAGE1_NO_SEMANTIC_GATE=1` only because
the current compiler's region-escape pass for this retained renderer unit
remained at 99% CPU without output for 72 seconds in the observed run before
being stopped. This bypass is diagnostic: it does not count
as a passing semantic-enabled full suite.

Observed on the current host:

- Off-screen Skia: 16 iterations, average `535987 ns`, pixel digest
  `26b1baa0682e064d`; a fresh process reproduced the digest.
- Public hello showcase workflow: 70 commands, 25 semantic nodes, 19 custom
  art commands, deferred commands on both sides of retained drawing, two
  generation-bound deferred images (`2 -> 3`), 16 render iterations averaging
  `4919679 ns`, pixel digest `f8cc2ba20c07b5bd`; a fresh process reproduced it.
- All five showcase pages and nine state/scale variants rendered: focus,
  high contrast, light high contrast, light, RTL, dialog, 2x, hover, and
  pressed. The 1x pages
  are 1180x800; the retina frame is 2360x1600.
- The AppKit/Skia compositor passed its off-screen CoreGraphics presentation
  check (`render_ns=8872000`, pixel digest `96591d2368f57d1a`).

The compiler's small semantic refinement gate passes at this compiler
revision. However, a semantic-enabled `check_skia.sh` remained at 99% CPU for
72 seconds while compiling `src/platform/skia/ui_skia.elisa` and was stopped;
the integrated retained text-lifecycle fixture showed the same behavior for
70 seconds. Thus the end-to-end suite is not recorded as green. Performance
and Unicode gates do pass in renderer-only diagnostic mode: the current
32-iteration benchmark reported `first_frame_ns=11560000`,
`layout_ns=5147000`, `paint_ns=22494000`, `text_ns=73104000`,
`text_input_ns=673000`, 221 large-tree widgets/commands, and peak RSS
`3620864` bytes; UAX #29 15.1.0 passed all 1187 rows with pinned data hash
`ed9c5e92fd0911ccbeeb63c97cb19c519ea272ff1112ce843abd991582dd848f`.

The complete strict command remains `bash scripts/run_tests.sh` with the
pinned `SKIA_ROOT`; do not set `ELISA_UI_REQUIRE_REAL_SKIA=0` for an acceptance
run. A future validation refresh should rerun this exact matrix without the
semantic bypass once the compiler's large-unit analysis cost is resolved.

## Renderer policy and prior milestones

The earlier compiler-only command was:

```
ELISA_UI_REQUIRE_REAL_SKIA=0 ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/run_tests.sh
```

It is an edit-loop mode, not real-raster or release evidence. The historical
notes below record incremental shared-framework/rendering changes; the latest
toolchain and renderer status above supersedes any older statements about
whether the pinned Skia build exists or whether the complete suite passed.

`UiLocalization::text_direction` now resolves a bounded paragraph base
direction from the first strong Unicode scalar, with locale fallback for
neutral-only text; bidi shaping and reordering remain renderer-owned.

`UiInspector::Frame.text_metrics` now carries the active text metric generations
and bounded query/miss counters, keeping font/scale cache evidence available to
headless diagnostics.

The public `UiTextMeasureLayout` facade now exposes opt-in RTL hit-testing,
caret, and selection geometry while leaving mixed-run shaping to the renderer.

`UiTheme::metrics` now provides shared spacing, touch-target, focus-ring, and
corner-radius tokens, with enlarged interaction affordances in high contrast.
`UiTheme::scaled_metrics` applies normalized text scale to spacing and touch
targets with finite bounds, while existing explicit widget dimensions remain
application-owned.
`UiFlat::apply_metrics` and its typed-handle forwarding apply those tokens to
focus, text, slider, and choice painter state; corner-radius remains reserved
until a flat rounded-primitive path exists.
`apply_system_theme` now applies palette and geometry in one coordinated API,
so runtime contrast and text-scale changes cannot leave stale control
affordances behind; the underlying preference and theme setters retain their
documented invalidation semantics.
High-contrast geometry also enlarges checkbox and radio markers so choice
controls retain visible affordances at the selected contrast level.
The typed accessible-button fixture also verifies the combined high-contrast
and 2x text-scale target path without opening a window.
`UiInspector::frame_with_system_contrast` accepts the host contrast fact so
diagnostic geometry reflects the active platform profile instead of assuming
normal contrast.
`UiSkia::fill_themed_surface` and `fill_current_themed_surface` consume
Elisa-owned corner-radius/theme metrics through the narrow Skia bridge; the
full headless suite, including the recorder-backed Skia test, passes.
`UiSkia::fill_current_themed_surface` resolves the same Elisa preferences and
host contrast fact before emitting rounded surfaces; the full off-screen Skia
recorder suite passes.
