# Current validation

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


The following completed headlessly from this checkout:

```text
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/check_toolchain.sh
  stage1 branch=codex/wasm-sdk revision=c6948142f19d0fa66089ca33ab5718c435738f15 (ahead=85 behind=0 vs origin/main)
  product_sha256=56945beffa13240afdd004ac7590580b56f11c7406fc82c16309f6bd9025e574
  runtime_sha256=cb06532f0c37540284de4ceaa622d0da9193f113877ac391fb00bad4bf9ff1e9
ELISA_UI_REQUIRE_REAL_SKIA=0 ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/run_tests.sh
  source-size gate,
  capi, appkit, appkit canvas, appkit canvas keymap, capi bridge,
  controls, dialog, drop raii, event wire, gestures, hierarchy build/layout,
  raster, responsive, sdl3 keymap/text, text input, text layout, widget dispatch, widget handles,
  widget layout, widget inspector, widget reentrancy, widget theme adapter,
  ui harness, metrics,
  resource presentation, feature view, core invalidation, lifecycle, constraints, identity,
  localization, theme, validation, virtual-list and virtual-list semantics: PASS
  widget_large_tree_test (256-slot capacity, overflow, hostile geometry, rebuilds): PASS
scripts/check_source_sizes.sh
  all tracked Elisa modules are at or below 400 lines, every other source file
  (tests, shims, scripts, headers, docs; third_party excluded) at or below 600: PASS
scripts/check_global_names.sh
  all mutable module-global names are unique across the source tree: PASS
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/check_unicode_conformance.sh
  unicode UAX #29 15.1.0: 1187 rows passed (pinned data hash verified)
scripts/check_skia.sh (strict default, no SKIA_ROOT in this checkout)
  required real-renderer dependency gate: EXIT 2 (expected; pinned SDK/archive not installed)
ELISA_UI_REQUIRE_REAL_SKIA=0 ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/check_skia.sh
  Elisa painter compile-only edit loop: PASS (not renderer evidence)
scripts/check_appkit_skia.sh (with the pinned checkout configured)
  optional AppKit/Skia compositor and bitmap-context fixture: PASS
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/check_performance.sh
  retained-tree build, relayout, paint, Unicode text, UTF-8 input,
  large-tree capacity, and RSS safety gate: PASS
git diff --check: PASS
```

The current stage1 product also builds the hosted package end to end:

```text
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/build_wapp.sh hello
  wasm: wrote .../main.wasm and .../main.json
  packed .../build/hello.wapp
ELISA_UI_WASMBROWSER=../WasmBrowser bash scripts/check_wapp.sh build/hello.wapp
  hosted package: compiler-independent profile/import/export inspection passed
```

This supersedes the older `/tmp/elisa-ui-stage1-p4` validation note: the
clean sibling checkout at `c6948142f19d` is the selected compiler product and
the fresh component build now passes. Runtime launch and device execution
remain separate fixtures.

`bash scripts/build_native.sh hello` likewise produces `build/hello_native`.

The 2026-09-07 gates compile the complete AppKit canvas entry point and run the
off-screen canvas fixture through `scripts/check_appkit_canvas.sh`; the bridge,
semantic callbacks, bundle/signature checks, and PNG frame all pass without
ordering a window onscreen. The explicit compiler-only suite
`ELISA_UI_REQUIRE_REAL_SKIA=0 bash scripts/run_tests.sh` passes from this
revision, including the AppKit canvas keymap and text paths; strict default
mode intentionally stops until the pinned Skia dependency is installed. The
Skia custom painter boundary compiles headlessly through
`scripts/check_skia.sh`; no foreground window is required. With a checkout at
the pinned revision and the lockfile's CPU-raster archive, the same gate also
links the production C++ host shim and runs
`test/skia_offscreen_test.elisa` against a real off-screen `SkSurface`, checking
background, rounded-fill, gradient, circle, triangle, and CoreText-backed glyph pixels
before writing a PNG. `scripts/check_appkit_skia.sh` also builds the optional
Skia AppKit product and verifies its CoreGraphics compositor against a bitmap
context without opening or activating a window.
The gate rejects AppKit imports in that shim even when no SDK is installed.
The repository intentionally keeps the SDK/build output external because it is
multi-gigabyte; the lockfile and GN arguments make the host fetch reproducible.
Its Elisa-owned `UiSkia::render()` entry
point now owns command replay and normalizes direct painter geometry before the
opaque canvas FFI, leaving the C++ shim with primitive SkCanvas calls only.
The custom host can use the exported one-shot `elisa_skia_render_frame` entry
point, while explicit attach/render/detach remains available to hosts that need
phase control. Skia font metrics are queryable before surface attachment
because they do not depend on a live canvas. The measured text planner is
backend-neutral, while `UiSkia::draw_text_block` uses the active borrowed
frame typeface for width, ascent, and line spacing, then applies explicit
horizontal and vertical alignment before clipping and replaying each line from
Elisa-owned layout state. Ready generation-bound typefaces can use the bound
layout/block helpers, including primary/fallback selection, without exposing
native font handles to widget code. Unavailable-font layouts reset shared line
ranges before returning, so stale measurements cannot leak into diagnostics;
soft hyphen/slash breaks retain punctuation on the preceding line, and lines
outside a clipped block are retained for diagnostics but skipped at the FFI.
The scalar-column planner now follows the same punctuation-preserving soft-break
policy as the measured planner.
Skia scale changes now clear borrowed renderer bindings and expose the active
scale in the read-only renderer snapshot before a replacement frame proceeds.
The frame boundary also supports an explicit logical-to-physical scale with a
balanced save/restore transform, including cleanup of any outstanding clips.
`UiSkia::surface_lost()` preserves retained Elisa state while invalidating the
borrowed canvas; a monotonic surface-generation token distinguishes loss and
recreation for hosts without exposing native pointers to the framework.
Direct rounded fills and image placement normalize malformed geometry in Elisa
before crossing the Skia FFI; empty destinations are rejected by the helper
contract and its headless recorder.
Immediate custom surfaces also support an Elisa-owned two-stop linear gradient;
the narrow bridge only constructs the backend shader after Elisa validates the
orientation, alpha, and destination geometry.
Convex custom polygons are bounded to 32 points and fan-triangulated in Elisa
through the existing triangle primitive, so no native path object or lifetime
enters the custom backend.
Their outlines are now closed in Elisa by reusing the validated line primitive;
no additional native path state is introduced.
Custom controls can also push a rounded clip through the same bounded typed
scope ledger; Elisa clamps its radius and the bridge forwards only the resulting
rectangle/radius to Skia's `clipRRect`.
`UiSkia::render_checked()` replays only the bounded retained batch and reports
when `UiCore` dropped commands at capacity, so oversize frames are observable
without an unbounded allocation.
`UiCapabilities::Snapshot` now reports a typed renderer profile: native
controls, SDL3, CoreGraphics fallback, Skia, hosted commands, or headless.
`test/skia_painter_test.elisa` (its checks live in phase files under
`test/skia_painter/`) records the full six-command replay through a
headless FFI shim, including clip and scale balancing and stale-handle cleanup.
Skia retained rectangles use an Elisa-bounded rounded-corner policy and a
narrow `SkRRect` primitive without changing the six-command wire format.
The same policy emits a narrow white hairline stroke; shadows remain explicitly
implemented as a target-specific Skia blur primitive with opacity, offset, and
blur values selected by the shared Elisa style record. The private
`ui_skia_style.elisa` extension lowers those values to FFI arguments, so neither
stroke weight nor shadow appearance is invented by the C++ bridge.
`UiPaint::rounded_rect_style` is the single Elisa-owned style policy consumed
by both the Skia painter and the CoreGraphics fallback, so radius/elevation and
hairline values cannot drift between custom backends. Custom fills retain the
shared rounded-corner and subtle hairline treatment; elevation is an explicit
`UiCore::fill_elevated` side-band bit that additionally enables the stronger
shadow treatment.
The Skia shadow pass uses a transparent source paint, so the blur cannot tint or
cover the retained control silhouette.
The custom painter also accepts a borrowed opaque `SkImage*` for destination
placement and alpha compositing; Elisa validates the rectangle and never retains
or frees the host-owned image handle. The headless Skia recorder covers valid
image draws and rejects null, zero-sized, and fully transparent requests.
`UiSkia::draw_ready_image` additionally checks the generation-safe logical
resource state, so loading, failed, cancelled, and recycled handles cannot paint.
The optional Elisa-owned image binding table associates host image handles with
exact resource generations; `draw_bound_image` cannot accidentally reuse a
pointer from another logical asset, and unbind/clear remain explicit before host
disposal.
`UiSkia::draw_ready_text` applies the same gate to borrowed host `SkTypeface*`
handles before drawing text, keeping font lifetime and fallback ownership out of
the framework ABI.
The optional generation-keyed font binding table provides the same strict form
for draw and metric queries, preventing a ready logical font from being paired
with another cached typeface.
The corresponding ready-font width, ascent, and line-height queries use the
same borrowed typeface, so custom layout metrics and Skia text rasterization
share one font authority.
Selection geometry now intersects byte ranges with each measured line in Elisa,
normalizes both endpoints to grapheme boundaries, and clips aligned rectangles
to the destination before Skia paints them. `UiSkia::fill_text_selection()`
keeps that fill behind text and owns its temporary clip scope; no selection
policy or range arithmetic crosses the native boundary.
`UiSkia::text_caret_rect()` and `UiSkia::draw_text_caret()` share that layout
and metric path for caret placement, leaving blink scheduling in widget state
and clipping the painted caret to its destination.
Ready generation-bound typefaces can now scope selection and caret painting
through the same font binding gate as text blocks, including primary/fallback
selection; unavailable or stale resources return empty layouts without
crossing the Skia boundary.
The Skia adapter also keeps a bounded byte-keyed grapheme-width cache in Elisa,
keyed by active font handle and normalized size; scale/binding resets clear it
and oversized clusters bypass the copy budget.
Image placement now has an Elisa-owned `ImageFit` policy: Stretch preserves the
legacy destination, Contain centers an aspect-preserving image, Cover centers a
crop inside a temporary clip, and ScaleDown avoids enlarging an asset that
already fits. Source dimensions are validated before the borrowed `SkImage*`
crosses the narrow bridge, and bound-resource variants reuse the same
generation-safe image gate. A bound image can also consume its
generation-scoped `UiResources::intrinsic_size()` metadata directly, keeping
decoded dimensions out of application widget state. Rounded image helpers
compose a typed rounded clip around that fitted destination, reusing the same
Elisa scope ledger for avatar/card presentation.
Fitted bound-image entry points prune disposed generations before their state
checks, so an invalid request cannot strand an opaque image handle in the
bounded binding table.
Skia rectangle normalization now also bounds the derived far edge: Elisa
clamps positive-edge extents before the FFI, while the native bridge rejects
out-of-envelope sums and negative source-crop origins from direct foreign
callers. The headless painter and off-screen host fixtures cover these
fail-closed cases without presenting a window.
Generation-bound source crops additionally consume verified intrinsic image
metadata when present, clamping source extents in Elisa for both immediate and
deferred resource commands; metadata-free resources keep the envelope-only
behavior.
The optional AppKit/Skia compositor now checks the packed Skia ABI major before
allocating a surface or invoking the Elisa callback; an incompatible runtime
returns the pre-frame rejection sentinel so CoreGraphics fallback remains safe.
Interactive text blocks now compose selection, glyphs, and caret painting in
one measured pass with one clip scope, preserving selection-before-text and
caret-after-text ordering while leaving blink scheduling in widget state.
The same compound operation has generation-bound primary/fallback wrappers, so
font-resource controls keep one borrowed typeface scope across layout and all
three painted layers.
- The AppKit/Skia replay contract now reserves zero for rejection before
  `app_frame`; negative results cover consumed-but-unpresentable frames and
  late native presentation failures. The C++ host preserves that distinction,
  allowing CoreGraphics fallback only when Elisa has not mutated application
  state; `test/appkit_skia_host_test.cpp` covers both paths off-screen.
The C++ bridge wraps each borrowed typeface in a temporary `sk_sp` reference
for SkFont's ownership contract without transferring disposal authority from
the host.
Attaching a live `UiSkia` canvas upgrades a custom profile to `Renderer.Skia`.
That selection also enables the `scale_changes` capability used by the
balanced logical-to-physical frame transform.

The shared `examples/hello/app.elisa` now uses `UiHandles::Handle` values for
every retained widget on SDL3, AppKit canvas, and WasmBrowser; only the
backend callback's legacy widget index is converted through the explicit
`UiHandles::index` escape hatch.

The modal/back-policy fixtures also run headlessly: AppKit canvas Escape gives
an active `UiDialog` first refusal, SDL3 consumes queued Escape facts for both
the modal and a `Consume` navigation entry before they reach `app_event`, and
WasmBrowser applies the same policy in its synchronous dispatcher.
`test/appkit_canvas_keymap_test.elisa`,
`test/sdl3_event_order_test.elisa`, and `test/wasmbrowser_dispatch_test.elisa`
cover the typed `Back` result and ensure unmodalized input remains unchanged.

The AppKit checks use activation policy prohibited and the custom canvas smoke
path; no window is shown or foregrounded. The hello app's new
`UiFlat::handle` entry point is covered by `test/widget_dispatch_test.elisa`.

The hosted component's earlier `expected i64, found i32` validation failure was
caused by the stale `/tmp/elisa-ui-stage1-p4` product. The clean sibling
compiler at `c6948142f19d` now emits a component that passes the linker and
package inspection; runtime launch and device execution remain separate gates.
The framework now declares its `Host.Present`, `Host.Layout`, and
`Host.Clipboard` permission family explicitly; manifest capabilities remain a
separate host-enforced security boundary.
