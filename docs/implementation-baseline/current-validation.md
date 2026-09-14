# Current validation

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._

## Refresh 2026-09-14 (code through f5d991d)

Current host: macOS 26.6.2 (Darwin 25.6.0), arm64; Homebrew clang 23.1.1.
The UI worktree is not clean: existing AppKit canvas, SDL3, and paint changes,
including the untracked SDL3 image module and fixture, were preserved and
excluded from the commits recorded here.

```text
scripts/check_toolchain.sh
  stage1 branch=codex/wasm-sdk revision=9791a8e1cd924bb03e43cb46da2d3530b4c9fbb0
    (ahead=0 behind=0 vs origin/main)
  product_sha256=78a8cb9da1443a420d2c6bab437339628bd285a8993ee4f9a959af0ffb034d15
  runtime_sha256=f9f7c011927606bf15c6feb62855ca4885d86b6efd5466193274a8aaccf94afb
scripts/check_source_sizes.sh / check_global_names.sh
  Elisa modules <=400 lines; other source <=600; mutable globals unique: PASS
scripts/check_refinements.sh
  semantic-enabled refinement diagnostics and framework laws: PASS
SKIA_ROOT=/tmp/elisa-skia-check-20260914 (pinned revision 9c7b2dffb2433f5a0cc2b77f06025a09126807ed)
  libskia.a sha256=39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775
  build provenance verified: PASS
check_skia.sh with ELISA_STAGE1_NO_SEMANTIC_GATE=1, real-raster requirement left at 1
  off-screen replay: pixel_digest=26b1baa0682e064d; 16 iterations, 535987 ns average
  public showcase: pixel_digest=f8cc2ba20c07b5bd; 70 commands, 25 semantics,
    19 art commands, deferred=2, resource_deferred=2, generations=2->3,
    16 iterations, 4919679 ns average; fresh-process digest stable
  five pages plus focus/high contrast/light/RTL/dialog/2x/hover/pressed PNGs: PASS
check_appkit_skia.sh with ELISA_STAGE1_NO_SEMANTIC_GATE=1
  off-screen CoreGraphics compositor: pixel_digest=96591d2368f57d1a: PASS
check_performance.sh with ELISA_STAGE1_NO_SEMANTIC_GATE=1
  32 iterations: first frame 11560000 ns, layout 5147000 ns, paint 22494000 ns,
  text 73104000 ns, text input 673000 ns, large tree 221 widgets/commands,
  peak RSS 3620864 bytes: PASS
check_unicode_conformance.sh with ELISA_STAGE1_NO_SEMANTIC_GATE=1
  UAX #29 15.1.0: 1187 rows, data sha256=ed9c5e92fd0911ccbeeb63c97cb19c519ea272ff1112ce843abd991582dd848f: PASS
test/text_lifecycle_workflow_test.elisa and test/showcase_workflow_test.elisa
  public retained editing/validation/resource relayout/teardown and app workflow: PASS
  (both executed in stage1 diagnostic mode with semantic gate disabled)
test/virtual_list_test.elisa
  latest stage1, semantic gate enabled: shared-pool exhaustion, cross-owner
  identity preservation, lazy initialization and global count: PASS
test/text_lifecycle_workflow_test.elisa
  diagnostic mode: identical replacement clears an IME mark and invalidates
  paint/semantics while preserving the text: PASS
scripts/package_release.sh
  injected copy failure in an isolated output: old bundle content preserved;
  staging and backup directories cleaned: PASS
test/sdl3_image_binding_test.elisa (pre-existing uncommitted worktree addition)
  diagnostic mode with SDL dummy driver: upload/readback, fit, alpha,
  replacement, generation reuse and renderer teardown: PASS
```

Semantic-enabled compilation of src/platform/skia/ui_skia.elisa remained at
99% CPU with no output for 72 seconds on compiler
9791a8e1cd924bb03e43cb46da2d3530b4c9fbb0 and was stopped. The new retained
text lifecycle fixture showed the same large-unit semantic-analysis delay at
70 seconds. This is not a renderer failure: the
same fixtures pass with the semantic gate bypassed, but it prevents recording
the complete suite as passing. The current small refinement gate does pass
with semantic analysis enabled. run_tests.sh was not completed on this latest
compiler revision; the earlier compiler-only full run stopped on separate
compiler/platform/linker issues and is not treated as acceptance evidence.

The WasmBrowser checkout was at
3ac9b25b0ea74000846625f46c2115ac93d16cf1 with pre-existing local changes; its
WIT SHA-256 remains
9032a1c59a5495d4868bc7cdf494153096708ff6f2321b4ea2ffeff752c627d6. The
standalone wasm-sdk checkout was at fa832f0e812254b0edb0447a17078397911c3d01
and also had pre-existing local changes. wasm-component-ld was not on PATH,
so the hosted component gate remains unavailable in this refresh.

## Refresh 2026-09-12 (main `a17b5c1`)

Fresh UI-00 gates from this checkout (macOS arm64, stage1 `986a30b9d6a1`):

```text
bash scripts/check_toolchain.sh
  stage1 branch=codex/wasm-sdk revision=986a30b9d6a165ae4a38ac8683687ee0e47b02a4 (ahead=20 behind=72 vs origin/main): PASS
bash scripts/check_source_sizes.sh
  all Elisa modules within 400 lines; every other source file within 600: PASS
bash scripts/check_global_names.sh
  all mutable module globals unique: PASS
bash scripts/check_refinements.sh
  framework discharges its own laws: PASS
bash scripts/build_native.sh hello
  built build/hello_native (2.3M): PASS
SDL_VIDEODRIVER=dummy ELISA_UI_SMOKE_FRAMES=1 ./build/hello_native
  exit 0: PASS
bash scripts/check_capi.sh
  C example passed: PASS
bash scripts/check_appkit_canvas.sh
  fresh-process PNG digest sha256=fe983e37bd348cf130b6e8aa0c09aee733f934c6866df0de362d04e34a8da880, bridge/bundle/signature: PASS
bash scripts/check_appkit.sh
  all checks passed: PASS
bash scripts/check_performance.sh
  benchmark passed (first_frame_ns=49721000 layout_ns=27872000 paint_ns=77312000 text_ns=75557000 text_input_ns=3164000 peak_rss=6062080): PASS
bash scripts/check_unicode_conformance.sh
  UAX #29 15.1.0: 1187 rows passed: PASS
PATH="$HOME/.cargo/bin:$PATH" bash scripts/check_wapp.sh
  built from this tree; profile, imports and exports inspected and JS-free: PASS
  (requires wasm-component-ld 0.5.30 on PATH; build_wapp.sh now preflights this with a hint)
bash scripts/check_uikit.sh
  fresh-process PNG digest sha256=31d5af91003c0f43cfd327e7c8abc34173a89bf66223afb624815bc2895a7833, simulator/device/ABI/off-screen: PASS
bash scripts/check_gtk.sh
  real GtkWindows/Buttons/Entries built, typed, shaped, coloured: PASS
bash scripts/check_win32.sh
  PE32+ image links from real Windows headers, zero declines: PASS
bash scripts/check_uikit_simulator.sh
  both iOS backends run on a booted device (canvas + controls screenshots): PASS
bash scripts/check_core_linux.sh
  70 of the portable corpus compiled for aarch64 Linux, linked and passed there: PASS
bash scripts/check_gtk_linux.sh
  same fixture on aarch64 Linux against a real X server: PASS
bash scripts/check_uikit_touch.sh
  real system-level touch reached the retained model and semantic tree: PASS
bash scripts/check_skia.sh (strict default, no SKIA_ROOT)
  Elisa painter + AppKit compositor entries compile; real-renderer checks skipped without the pinned checkout: PASS-as-skip (not raster evidence)
ELISA_UI_REQUIRE_REAL_SKIA=0 bash scripts/check_skia.sh
  compiler-only edit loop: PASS (not renderer evidence)
bash scripts/check_appkit_skia.sh / check_showcase_skia.sh (no SKIA_ROOT)
  skipped, exit 0: NOT VERIFIED here (needs pinned checkout from third_party/skia.lock)
bash scripts/check_android.sh / check_android_ime.sh (no SKIA_ROOT/SDK)
  skipped, exit 0: NOT VERIFIED here (needs SDK + NDK + emulator + Android Skia build)
bash scripts/check_toolchain.sh --report
  prints the resolved compiler revision + product/runtime SHA-256; downgrades dirty/stale to warnings: PASS
  (called by build_native.sh, build_appkit_canvas.sh, and build_wapp.sh so every build shows its toolchain)
bash scripts/check_capi.sh
  C example passed; header↔symbol cross-check: 7 host-facing functions and 6 app-facing callbacks agree both directions: PASS
test/services_test.elisa
  permission/picker state machines, anti-prompt gate, settings sync, logical selection, owner disposal: PASS
test/build_test.elisa
  framework API version, packed version, and typed compatibility verdicts: PASS
test/accessibility_metadata_test.elisa
  Image/Group/List/Status/Alert roles retained; live status/alert keep text and revision: PASS
bash scripts/check_appkit_canvas.sh, scripts/check_uikit.sh
  AppKit/UIKit role mappings for the new semantic roles build and pass off-screen: PASS
test/remote_test.elisa
  capability limitations report missing text/IME/semantics/clipboard/file-dialog services: PASS
test/shortcuts_test.elisa
  shortcut precedence (reserved > editable > app command > menu), exact modifiers, repeat, idempotence: PASS
test/word_navigation_test.elisa
  Option/Control+Left/Right, Shift word selection, and word deletion reach the shared helpers from the keyboard: PASS
test/virtual_list_test.elisa
  bounded realization: stable visible slots, generation change on return, owner isolation, slot budget: PASS
test/sdl3_device_loss_test.elisa
  SDL render targets-reset/device-reset/device-lost handled headlessly; renderer recreated, app state preserved: PASS
test/ui_table_test.elisa
  weighted column growth, maximum caps, deficit sharing, minimum floor, overflow report: PASS
test/ui_tree_test.elisa
  depth-first visible order, expansion/collapse, reveal, visible navigation, invalid registration: PASS
test/stress_test.elisa
  50 sessions, resource overflow/churn, 5000-event burst, command overflow, hostile geometry: PASS
bash scripts/check_rust.sh
  safe Rust wrapper over the C ABI links and passes (event/text/IME/viewport); skips without rustc: PASS
scripts/package_release.sh
  emits build/release/elisa-ui-0.1.0 with LICENSE, release.json (version/revision/toolchain), and files.sha256; integrity verified: PASS
git diff --check: PASS
```

The complete portable `test/*_test.elisa` corpus was run in batches (the
one-shot `run_tests.sh` exceeds the 120s tool timeout, so each fixture was
compiled/linked/run individually with the same stage1, runtime, SDL, and
stub link inputs). Result after the services/build/shortcuts/semantics/remote
additions: 80 of 80 passed, 0 failed, 5 real-Skia host fixtures skipped.

```text
batch 1 (15): accessibility_geometry, accessibility_metadata, capabilities,
  capi_app_text, capi_bridge, capi_lifecycle, capi_widget_handle, color_pack,
  constraints, controls, core_invalidation, dialog, drop_raii, event_queue,
  event_wire
batch 2 (15): feature_view, gestures, hierarchy_build, hierarchy_layout, identity,
  lifecycle, localization, metrics, mobile_surface, navigation, raster, remote,
  resource_presentation, resource_state, responsive
batch 3 (15): sdl3_event_order, sdl3_keymap, sdl3_lifecycle_stop,
  sdl3_pointer_event, sdl3_resize_event, sdl3_text, sdl3_wait_event,
  sdl3_window_routing, showcase_workflow, tasks, text_input, text_layout,
  text_metrics_cache, theme, ui_harness
batch 4a (15): ui_state, validation, virtual_list_semantics, virtual_list,
  wasmbrowser_dispatch, wasmbrowser_input_mapping, widget_dispatch,
  widget_handles, widget_image, widget_inspector, widget_large_tree,
  widget_layout_geometry, widget_layout_scroll, widget_layout_text,
  widget_layout_visual
batch 4b (9): widget_motion, widget_reentrancy, widget_theme_adapter,
  controls_flat, skia_painter, unicode_conformance, appkit_canvas_appearance,
  appkit_canvas_keymap, appkit_canvas_surface
uikit batch (4): uikit_controls, uikit_input, uikit_surface, uikit_text_input
policy fixtures (7): build, services, shortcuts, word_navigation, ui_table, ui_tree, sdl3_device_loss
```

The five real-renderer fixtures excluded by `run_tests.sh` itself
(`skia_offscreen_test`, `showcase_skia_test`, `showcase_app_skia_test`,
`storefront_skia_test`, `appkit_skia_host_test`) are owned by the Skia gates
above and remain NOT VERIFIED here without `SKIA_ROOT`.

Full `scripts/run_tests.sh` exceeds the default 120s tool timeout on this
machine; it is not recorded as pass/fail here. The gates above are the
verified subset for this refresh.

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

The hosted package does **not** currently build, and this is the note that used
to say it did. `scripts/check_wapp.sh` is now in `scripts/run_tests.sh` and
builds the package before inspecting it; the first time it did so it failed:

```text
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/check_wapp.sh
  wasm-ld: error: initial memory too small, 2344864 bytes needed     # fixed: 64 pages
  error: failed to resolve import `env::ctx_string_views_eq`         # open
```

The first was ours and is fixed in `scripts/build_wapp.sh`: the framework's
static data had outgrown 32 pages of initial linear memory, and data segments
must fit at link time regardless of runtime growth.

The second is the compiler repo's. `ctx_string_views_eq` is the runtime helper a
match over string views compiles to; `build/runtime/elisacore_runtime.o` defines
it and the cached wasm runtime object does not, and `--allow-undefined` cannot
absorb it because component validation then rejects the leftover `env` import.
Writing a stand-in for a compiler-internal ABI symbol in this repo would be the
same mistake as writing the Windows runtime host here.

The target has been unlinkable since roughly 2026-09-10, and every suite was
green throughout, because the gate inspected whatever package was left in
`build/` and nothing invoked the gate. Runtime launch and device execution
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
