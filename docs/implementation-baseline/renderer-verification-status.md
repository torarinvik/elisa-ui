# Renderer verification status

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


## Latest verification: 2026-09-17

The 2026-09-17 RTL scrollbar paging follow-up is covered by the exact current
tuple in `test/showcase_skia_performance_budgets.json`: compiler revision
`bfedb0d707a00797ddd16341f21a8b6e0a9677af`, source bundle
`85c9f05ff5532e0bd43273aec8e2f0dfce6f21d3db6301ddf2251cd7a586957f`, median
`11.512 ms`, maximum `12.186 ms`, and tail digest
`1ac21e37972207bb`. The focused Elisa regression and Unicode corpus also pass;
the compiler checkout is intentionally dirty and was explicitly allowed for
this current-product verification.

The current required CPU-raster tuple uses the clean latest local compiler
`main` revision `5329edfdbefa27b5c1c51253da0073256ed51058`, with stage1 product
SHA-256 `03fb7200424b6849ea3243c33e774270b4e8909a080136d05092251254b52024`
and runtime SHA-256
`85f1107eef00a7dd903e511df366b8b6cade4d8573cf0478f1de91604ea5beb9`.
The exact Showcase budget for this source bundle records a 20.013 ms median
and 23.934 ms maximum over 21 fresh-process samples; the tail digest is
`1ac21e37972207bb`.

The pinned Skia checkout and CPU-raster archive are now built locally. From a
fresh checkout, provision them without opening a window:

```
export SKIA_ROOT=/path/to/elisa-skia
export SKIA_OUT="$SKIA_ROOT/out/elisa"
bash scripts/build_skia.sh
```

Historical compiler tuples remain recorded in the budget manifest for
comparison, but the required gate uses only the clean latest 5329edfd tuple
above.
```sh
PATH="/path/to/depot_tools:$PATH" \
ELISA_UI_STAGE1=/path/to/clean-elisa-compiler \
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

The required showcase renderer gate now compiles its Elisa fixture with `-O2`
and also measures the public million-item list workflow plus its resulting
Skia CPU-raster frame. It collects seven samples in each of three fresh
processes after two warmups. Reinitialization, pixel scanning, and PNG encoding
are outside the measured interval; the gate separately checks that the tail
pixels differ from the initial list and match across all samples/processes.
Exact host, compiler product/runtime, Skia source/archive/build, workload flags,
dimensions, and source-bundle provenance are required to select its budget.

Observed on the current host:

- Off-screen Skia (`5329edfd`): 16 iterations, average `409528 ns`, pixel
  digest `26b1baa0682e064d`; a fresh process reproduced the digest.
- Public hello showcase workflow: 70 commands, 25 semantic nodes, 19 custom
  art commands, deferred commands on both sides of retained drawing, two
  generation-bound deferred images (`2 -> 3`), 16 render iterations averaging
  `4522882 ns`, pixel digest `f8cc2ba20c07b5bd`; a fresh process reproduced it.
- All five showcase pages and nine state/scale variants rendered: focus,
  high contrast, light high contrast, light, RTL, dialog, 2x, hover, and
  pressed. The 1x pages
  are 1180x800; the retina frame is 2360x1600.
- The AppKit/Skia compositor passed its off-screen CoreGraphics presentation
  check (`render_ns=11272500`, pixel digest `96591d2368f57d1a`).
- Million-item Showcase workflow plus Skia tail frame: the latest `5329edfd`
  tuple has a recorded median of `20.013 ms` and maximum `23.934 ms`, within its
  `50 ms` median / `80 ms` maximum limits. Pixel
  digest `1ac21e37972207bb` was stable across the benchmark and fresh processes.
  Raw samples and the exact source-bundle reference tuple are in
  `test/showcase_skia_performance_budgets.json`.

The strict Skia gate, semantic-enabled UI suite fixtures, Unicode corpus, and
standalone exact M5 performance-budget gate passed with the clean current
`5329edfd` product. The existing retained-tree reference (recorded with the
8d7 product) has three-process
aggregate medians of 8.065 ms first-frame batches, 3.780 ms layout, 16.373 ms
paint, 44.392 ms text, 0.437 ms text-input, and 0.135 ms for 128 anchored
virtual-list windows; maximum RSS was 3,653,632 bytes. The exact tuple keeps
source/compiler hashes strict and adds only a bounded scheduling-variance
margin around timings. The full matrix now links the Win32 image through the
Elisa debug-referee adapter, and the Linux cross-target plus GTK legs pass.
Android Skia/device legs remain environment-dependent; the hosted open
vertical-slice now builds a JS-free component package through the repaired
intrinsic/runtime path. The
exact current outcomes are summarized in [`current-validation.md`](current-validation.md).

The complete strict command remains `bash scripts/run_tests.sh` with the
pinned `SKIA_ROOT`; do not set `ELISA_UI_REQUIRE_REAL_SKIA=0` for an acceptance
run. Set `ELISA_UI_STAGE1` to a clean latest compiler build when the shared
`../Elisa-compiler` worktree is dirty.

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
