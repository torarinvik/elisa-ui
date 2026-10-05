# Validation — 2026-10-05

This dated note records fresh results after the macOS/Xcode and Homebrew repair.
It supplements the [rolling validation log](current-validation.md), not the
broader acceptance matrix.

## Retained-tree performance

Stage1 revision `8e08cd3397b1680c61bfb76b70e1a76541522e3d` (product SHA-256
`f7d4dc3c2a2a126da19723abdcd806bf99f08a71cc8bf15a35c2f508e2e19b9d`, runtime
SHA-256 `b51e6114f0576681e432e1162a3dbdcdac46c140d3b7e7256c0069be0bd11897`)
was measured on macOS 27.0.1 build 26A434, Mac17,4 / Apple M5, with Homebrew
clang 23.1.1. `test/performance_budgets.json` records 21 samples per phase
across three processes: median batches of 4.208 ms first-frame, 2.108 ms
layout, 6.382 ms paint, 24.084 ms text, 0.621 ms text input, and 0.087 ms for
128 virtual-list windows; peak RSS was 4,014,080 bytes. A fresh strict
`ELISA_UI_REQUIRE_PERF_BUDGET=1 bash scripts/check_performance.sh` run passes
against this exact tuple. This is CPU and peak-RSS evidence; idle CPU,
allocation counts, GPU-upload latency, and mobile energy remain unmeasured.

## Native ABI and fixed-arena stress

With the default Xcode 27 developer directory and no `DEVELOPER_DIR` override,
`scripts/check_capi.sh`, `scripts/check_rust.sh`, and `scripts/check_go.sh` pass
for the ABI 1.2 retained-control surface. Fresh `capi_bridge_test` and
`capi_widget_handle_test` runs cover counted UTF-8, secure-field readback
denial, selection bounds, scrolling, virtual-row rebinding, stale/wrong-kind
handles, and arena exhaustion. `stress_test`, `widget_large_tree_test`,
`widget_layout_text_test`, `lifecycle_test`, `resource_state_test`, and
`mobile_surface_test` compile, link, and pass, covering fixed-arena bounds,
large text, hostile geometry, resource churn, repeated view/session lifetimes,
and lifecycle interruptions. No expandable arena exists, so that part of the
plan remains open.

The independent WasmBrowser SDK Typewriter SDL renderer smoke passes with its
pinned font and does not link elisa-ui. These focused results do not substitute
for `scripts/run_tests.sh` or physical-device/accessibility acceptance.

## Shared Hello application adapter

`examples/hello/app.elisa` now keeps initialization, typed events, committed
text, IME composition, widget events, and frames behind the namespaced
`HelloApp` module; the top-level `app_*` functions are forwarding adapters.
`scripts/build_native.sh hello` plus a one-frame SDL dummy-video smoke,
`scripts/build_appkit_canvas.sh hello`, and
`scripts/build_uikit.sh hello simulator canvas` all pass.
The follow-up isolated `env::memcmp` to Stage1's in-module sview-equality
optimization: it synthesized a libc import even though the component runtime
has its own freestanding equality helper. A component-mode codegen branch now
calls that helper directly and leaves the native fast path unchanged. The new
compiler `wasm_component_sview_equality_smoke.sh` passes with a counted view
containing an embedded NUL. With the rebuilt Stage1 product
(`8e08cd33`, SHA-256
`13dfedc09eb4e6de272f8f0b69e0b791df0e5d5986e51d37fea84a942d3effd4`),
`scripts/build_wapp.sh hello` now emits and validates `build/hello.wasm` against
the component WIT world. The command still exits 3 before packaging because no
WasmBrowser CLI executable is available. An offline `cargo build --locked
--offline -p wb-cli --bin wasm-browser` attempt is currently blocked while
building the SDK's Elisa archives: Stage1 rejects the sibling
`wb_protocol/contract_parse.elisa:110` `in auto` return. Therefore no `.wapp`
was packed or launched, and hosted runtime acceptance remains unverified. The
UI `scripts/check_wapp.sh` now still rebuilds and WIT-validates the raw Hello
component when the CLI is missing, then reports package inspection and runtime
execution as skipped rather than skipping all hosted compilation. The
broader compiler `wasm_component_runtime_smoke.sh` independently stops earlier
on `env::__multi3` in its host-surface fixture; the focused sview-equality
gate passes. `scripts/check_wapp_resources_ui.sh` also compiled its
current-source resource-profile guest into a component, but did not complete
runtime validation: building the WasmBrowser validator with the current
Stage1 product fails on `in auto` region diagnostics in sibling SDK files
`wb_commerce/entitlement.elisa:82` and
`wb_protocol/contract_parse.elisa:110`. The guest compile is not a runtime
pass; the sibling SDK sources were not changed. A reusable framework-level
`UiApplication` API also remains unimplemented.

An entrypoint API probe confirmed a current Stage1 limitation: a minimal
callback value with type `fn(UiCore::Event) -> void` (also tested by mutable
reference) traps in LLVM `DataLayout::getAlignment`; the same probe with an
`i32` callback compiles. The callback registry prototype was discarded rather
than exposing an unusable API. The namespaced example adapter remains useful,
but the reusable typed entrypoint needs a compiler fix and is still open.

## Passive gesture surface and app-owned zoom

The retained gesture router now falls back from interactive hit-testing to the
topmost visible registered target containing the contact. This makes a blank
canvas/scroll area a usable gesture surface without inserting fake controls.
Hello reserves a real canvas panel and maps pinch scale into a bounded
app-owned preview zoom; rendering uses that scale for the artwork radius.
`hello_zoom_workflow_test` passes through `app_event` and the retained widget
callback, verifies empty passive space and overlapping-target paint order,
checks zoom-in/zoom-out and scale bounds, and confirms the emitted drawing
commands change size. `gestures_test`,
`widget_layout_scroll_test`, and `uikit_surface_test` also pass. Current-source
Hello builds pass for SDL, AppKit canvas, and UIKit simulator canvas; the SDL
dummy-video one-frame smoke passes. This is host/simulator-build evidence, not
physical-device pinch or stylus acceptance.

## Retained touch scrolling

Default retained scroll viewports now capture contacts when no explicit gesture
target owns them. `UiFlat` begins scrolling at the shared drag threshold,
includes displacement accumulated before that threshold, routes same-axis
movement through nested viewport edges, and advances bounded release momentum
on the retained frame clock. The shared reduced-motion preference suppresses
momentum while preserving direct touch tracking; focus loss and cancelled
contacts retire it. `touch_scroll_test` covers drag continuity, compatibility
pointer-capture cancellation, nested edge handoff, virtual-list positioning,
frame-clock inertia, reduced motion, and focus-loss cancellation.

`scripts/check_mobile_input.sh` passes all portable/mobile input regressions,
including the new fixture and UIKit host-surface test, on Stage1
`8e08cd3397b1680c61bfb76b70e1a76541522e3d`. These are deterministic host
checks, not physical-device scroll-feel acceptance.

## Toolchain recheck

With Xcode selected by the normal `xcode-select` setting and no
`DEVELOPER_DIR` override, `xcrun --sdk iphonesimulator --show-sdk-path`
resolves the installed iOS 27.0 SDK. The focused mobile-input gate and current
Hello SDL, AppKit-canvas, and UIKit-simulator builds all pass; the UIKit link
prints a nonfatal warning about `libSystem.B.tbd`. The one-frame SDL dummy
smoke passes. Do not set `DEVELOPER_DIR` globally to Command Line Tools for
these checks: that directory lacks the iPhone Simulator platform SDK.

## SDL3 retained text textures

The SDL3 painter now retains up to 32 blended text textures, with a 1 MiB
estimated pixel-cost limit and a 128 KiB per-entry cap. Keys compare exact
counted UTF-8 bytes, point size, and color; font generation, locale revision,
and `SDL_GetWindowDisplayScale` changes clear entries before reuse. Oversized
text bypasses key storage, and eviction/invalidation scrubs copied text bytes.
Font replacement and renderer teardown explicitly destroy retained SDL
textures.

`sdl3_text_cache_test` compiles, links, and passes against the dummy SDL video
driver. It verifies same-key hits, size/color key separation, locale and font
generation invalidation, 32-entry LRU eviction, over-capacity-text bypass,
fontless behavior, and renderer teardown. `sdl3_text_test` and
`sdl3_showcase_image_workflow_test` also compile, link, and pass with this
change. `bash scripts/bench_sdl3_text_cache.sh` measures the complete
`UiCore`→`UiPaint`→SDL3 render/present path for 21 samples of 256 paints in
each of three fresh processes. The cold-miss phase keeps text and size fixed
while changing color to force LRU misses and eviction; the warm-hit phase
repeats one exact key. Per-batch counters prove that the cold and warm phases
really take their stated paths.

On macOS 27.0.1 build 26A434, Mac17,4 / Apple M5, Stage1 `8e08cd33`
(`78a26e2c5142c84fc2fe6769281a445621ed10f13d750545ea26dd8e490e50d5`),
Homebrew SDL3 3.4.16 and SDL_ttf 3.2.2, the three process medians in ns/draw
were cold/warm `32015/4648`, `24324/3535`, and `24078/3441`; the median of
process medians is `24324/3535`, or `6.88x`. The first cold run is slower, but
all three runs show a similar ratio. This establishes a measured benefit for
repeated exact text/style on this reference host, not a cross-device budget.
Shared image-resource caching, caches for other text authorities, and broader text
shaping acceptance remain open.

## Skia simple-text fallback cache

`scripts/check_skia_offscreen.sh` passes on the pinned Skia revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`. The fixture verifies bounded
simple-text blob reuse, exact pixels against the previous `drawSimpleText`
path at fractional placement for a plain run under two colors and a separate
fallback-font run. It also checks exact-text/font/typeface key separation,
locale/scale, font-manager and quality invalidation, entry- and byte-cost LRU
bounds, oversized-entry bypass, and surface-loss clearing. The Apple shaper normally handles untracked text, so
this exercises the shared fallback cache directly; Arabic/Devanagari shaping
and the fresh-process replay digest also continue to pass. The gate used the
existing Stage1 product SHA-256
`78a26e2c5142c84fc2fe6769281a445621ed10f13d750545ea26dd8e490e50d5` from
revision `2691a64c7522c94eee0d5b0b930d1995c7376a3c`; the compiler checkout was
dirty, and `ELISA_ALLOW_DIRTY_STAGE1=1` was used without modifying that tree.

The Android ARM64 text shim compiles with the installed NDK 30 toolchain and
warnings-as-errors. The generated executable fallback now undefines NDK
`va_copy`/`va_end` macros before declaring Elisa's weak compatibility hooks.
Stage1 was rebuilt from compiler revision `2691a64c7522c94eee0d5b0b930d1995c7376a3c`
(product SHA-256
`a30ba6237db030cbe754f6b360f635b61903ba1154d5942870637b4e13546ff4`; matching
runtime SHA-256 `b51e6114f0576681e432e1162a3dbdcdac46c140d3b7e7256c0069be0bd11897`).
With Android NDK `30.0.16138531` and API 30,
`scripts/check_android.sh showcase` passes ARM64 link/export and APK
storage/16-KB-alignment checks against the pinned Android Skia archive;
`scripts/check_android_controls.sh showcase` also passes its JNI/export,
no-Skia/no-shared-C++ runtime, Java-bridge, and package-alignment checks. Both
device gates then passed on the Pixel_9 Android 17/API 37 AVD (emulator 37.1.11,
16-KB system image): the canvas rendered a non-uniform 1080×2424 frame in 57 ms,
retained button semantics were visible, and rotation plus HOME/resume repainted;
the controls Activity launched and produced a 24,498-byte screenshot. No
physical Android device was attached, and this is not a dedicated cache
benchmark; physical-device acceptance and Android cache timing remain open.
The gate's JNI check was also updated to verify the current exception-clearing
helper and its combined string-length guard rather than an obsolete source
spelling.
