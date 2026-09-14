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
`fd2cb3cff470319500db362e5fce2833cbe300de` and Skia revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`. The archive SHA-256 is
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`.

```sh
PATH="/path/to/depot_tools:$PATH" \
SKIA_ROOT=/path/to/elisa-skia \
SKIA_OUT="$SKIA_ROOT/out/elisa" \
bash scripts/check_skia.sh
```

`ELISA_UI_REQUIRE_REAL_SKIA` defaults to `1`; `check_skia.sh` therefore
requires and verifies the real pinned archive, renders pixels, checks stable
fresh-process replay digests, and writes the five showcase pages plus focus,
high-contrast, light, RTL, dialog, 2x, hover, and pressed images under
`build/`. This verification completed with semantic checks enabled and without
`ELISA_STAGE1_NO_SEMANTIC_GATE`; it supersedes the older compiler's prolonged
region-escape analysis noted in historical validation below.

Observed on the current host:

- Off-screen Skia: 16 iterations, average `536179 ns`, pixel digest
  `26b1baa0682e064d`; a fresh process reproduced the digest.
- Public hello showcase workflow: 70 commands, 25 semantic nodes, 19 custom
  art commands, deferred commands on both sides of retained drawing, two
  generation-bound deferred images (`2 -> 3`), 16 render iterations averaging
  `5684078 ns`, pixel digest `f8cc2ba20c07b5bd`; a fresh process reproduced it.
- All five showcase pages and nine state/scale variants rendered: focus,
  high contrast, light high contrast, light, RTL, dialog, 2x, hover, and
  pressed. The 1x pages
  are 1180x800; the retina frame is 2360x1600.
- The AppKit/Skia compositor passed its off-screen CoreGraphics presentation
  check (`render_ns=13470291`, pixel digest `96591d2368f57d1a`).

The strict Skia gate, semantic-enabled UI suite fixtures, Unicode corpus, and
standalone exact M5 performance-budget gate all passed with this compiler. A
separate full matrix attempt remains incomplete: its cross-target legs reported
Win32 `kill`/`sigaction` link failures, Linux cross-target failures, and a
WasmBrowser build missing `wasm-component-ld`. The SDL/Android checks skipped
because the Android Skia archive is not installed. The exact current outcomes
are summarized in [`current-validation.md`](current-validation.md).

The complete strict command remains `bash scripts/run_tests.sh` with the
pinned `SKIA_ROOT`; do not set `ELISA_UI_REQUIRE_REAL_SKIA=0` for an acceptance
run. This current verification used the default `../Elisa-compiler` checkout.

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
