# Renderer verification status

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


The reproducible compiler-only command is:

```
ELISA_UI_REQUIRE_REAL_SKIA=0 ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/run_tests.sh
```

It passes the complete headless suite, including the recorder-backed Skia
fixture. The required real-raster showcase gate is not locally executable yet:
`scripts/check_showcase_skia.sh` requires `SKIA_ROOT` at the pinned checkout,
and the host currently has neither that checkout nor the `gn`/`autoninja`
tooling needed to build it. This is an environment prerequisite, not evidence
of a renderer failure; CI or a provisioned host must run the strict gate before
claiming real-Skia pixel evidence.

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
