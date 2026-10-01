# Hosted surfaces (external GPU renderers in a panel)

An external renderer, such as an Elisa engine viewport, can draw into an
IOSurface-backed Metal texture ring. The AppKit canvas shows it over a panel as a
CALayer whose `contents` is that IOSurface. This path is zero-copy and does not
go through `drawRect`.

- Policy (pure Elisa): `src/core/ui_hosted_surface.elisa` (`UiHostedSurface`).
  - `sanitize`: clips the panel rect to the view and rejects non-finite values.
  - `pixel_extent`: converts panel points to renderer pixels, in the range 1 to 16384.
  - `decide` / `record`: choose between APPLY, REMOVE and NONE for each slot.
  - `contains` and `to_local_x/y`: pointer mapping.
- AppKit call (`src/platform/appkit/ui_appkit_canvas_hosted.elisa`):
  `UiAppKitCanvas::present_hosted(&shown, slot, surface, generation, frame, rect, view_w, view_h)`.
  Call it once per UI frame and slot. APPLY means the frame is on screen, so the
  app acknowledges it to the renderer. `remove_hosted` drops a slot, and
  `backing_scale()` gives pixels per point.
- Native side (`canvas_shim/hosted_surface.m`): 16 slots of
  `ElisaHostedSurfaceLayer`. The layer retains the IOSurface, and a same-surface
  re-render is shown by resetting `contents`. Other sublayers are never touched.

Example: `examples/viewport/`, built with `scripts/build_appkit_canvas_viewport.sh`.
It includes the engine through `build/elisa_engine_src`, which links to
`$ELISA_ENGINE_ROOT/src` (default `../elisa-engine-mocap`). The example resizes
the engine viewport to the panel's pixel size, draws a grid and a stick figure,
ticks, presents, and acknowledges on APPLY. Controls:

| Input | Action |
| --- | --- |
| Drag | Orbit |
| Right or middle drag | Pan |
| Scroll | Zoom |
| F | Frame the figure |
| 1 / 2 / 3 | Perspective / front / side |

## Validation

- `test/hosted_surface_policy_test.elisa` checks clipping, NaN and infinite
  values, retina rounding, caps, and every decision transition. It passes.
- `test/appkit_canvas_hosted_surface_test.m` composites the layer tree with
  CARenderer into a Metal texture and reads it back, with no window. It covers:
  - placement of two slots, one of them scaled;
  - a same-surface update;
  - move and resize;
  - the producer releasing the surface;
  - removal that leaves foreign layers alone;
  - invalid root, slot and surface.

  It passes and runs from `scripts/check_appkit_canvas.sh`.

## Open

The example app type-checks, but the full canvas app does not compile with any
available toolchain. Both `../Elisa-compiler/bin/elisac-stage1` and
`~/.elisac/stage1` are older than the elisa-ui sources: stock `examples/hello`
fails in `ui_flat_layout.elisa` and `ui_appkit_canvas_private.elisa`, and
rebuilding the compiler needs `--seed`. Once a current stage1 exists, run
`scripts/build_appkit_canvas_viewport.sh` and then
`ELISA_UI_SMOKE_FRAMES=1 build/viewport_appkit_canvas`.

## Three views in one layout

`examples/viewport/three_views_layout.elisa` hosts three engine viewports at once:
a perspective view above orthographic front and side views. Each view sits in its
own growing panel and uses its own `present_hosted` slot (0, 1 and 2). On every
sync each view is resized to its panel in pixels and redraws only when its scene
revision, camera or size changed. Changing one panel's grow factor resizes the
views next to it and leaves the perspective view untouched.
`scripts/check_viewport_three_views.sh` runs the test headlessly against a real
Metal device. It covers:

- two window sizes and a grow change;
- idle frames, which must not render;
- frame-selection centring in all three views;
- pointer routing.

Mutants that size every view from panel 0, or that redraw on every sync, fail the
test with codes 11 and 20. Build the window with
`ELISA_VIEWPORT_APP=three_views scripts/build_appkit_canvas_viewport.sh`.
Smoke frames run without showing the window, so no hosted layer is applied
there; the "applied" line only appears in an on-screen run.

The views live in one module global each and the scene is passed in by
reference. With stage1, a struct holding a viewport array and forwarded by
reference segfaults, a global array of structs is declined, and a scene read out
of a global optional traps inside `ViewportScene::tick`.
