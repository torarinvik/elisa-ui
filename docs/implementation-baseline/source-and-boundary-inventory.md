# Source and boundary inventory

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


Public framework modules are `UiCore`, `UiLifecycle`, `UiMetrics`, `UiState`, `UiTasks`, `UiCapabilities`, `UiEvents`, `UiPaint`, `UiRaster`,
`UiConst`, `UiWidgets`, `UiFlat`, `UiHandles`, `UiResources`, `UiResourcePresentation`,
`UiResponsive`, `UiVirtualList`, `UiConstraints`, `UiIdentity`, `UiTheme`,
`UiLocalization`, `UiValidation`, `UiFeatureView`, `UiDialog`, `UiNavigation`, `UiBack`, `UiGestures`, `UiTextLayout`, `UiTextMeasureLayout`, `UiTextInput`, `UiControls`, `UiCapi`, `UiAppKit`, `UiSkia`, `UiRemote`,
`UiAppKitNative`, `UiAppKitCanvas`, `UiSdl3`, `UiSdl3Draw`, `UiWasmBrowser`,
`UiMobileSurface`, and `UiInspector`. The application contract is
the top-level `app_init`, `app_event`, `app_text_input`, `app_text_editing`,
`app_frame`, and optional `app_widget_event` callbacks.

Externally imposed symbols are kept at the edges:

- C ABI declarations and exports in `include/elisa_ui.h` and `src/capi/`.
- SDL3/SDL_ttf C functions in `src/platform/sdl3/ui_sdl3.elisa`; the
  `UiSdl3Draw` module in `src/platform/sdl3/ui_sdl3_draw.elisa` owns renderer,
  font, raster, and painter state behind that boundary.
- CoreGraphics, CoreText, CoreFoundation, ImageIO, libobjc, and AppKit fact
  globals in `src/platform/appkit/ui_appkit_canvas_native.elisa`; typed controls
  bridge wrappers in `src/platform/appkit/ui_appkit_native.elisa`.
- WasmBrowser WIT imports/exports and canonical record encoding in the
  `src/platform/wasmbrowser/` backend modules; private clipboard staging,
  guest-memory validation, and text metric normalization live in
  `ui_wasm_host_state.elisa`.
- Cocoa object/protocol/selector entry points in
  `src/platform/appkit/appkit_shim.m` and `appkit_canvas_shim.m`. The canvas
  shim is one translation unit: the umbrella file holds the Elisa callback
  prototypes and `#import`s its fragments from `src/platform/appkit/canvas_shim/`
  (accessibility element, handle helpers, delegate, view, window, accessibility
  lifecycle), each under the 600-line source limit, and the policy gate reads all
  of them.
- Skia custom-rendering primitives in `src/platform/skia/skia_canvas_shim.cpp`;
  the source revision and CPU-raster build contract are pinned in
  `third_party/skia.lock`. A host still supplies the fetched SDK/build output;
  `ui_skia.elisa` and the generation-safe `ui_skia_resources.elisa` binding
  registry remain compiler- and headless-testable without it.
- Deferred Skia image fitting is also Elisa-owned: source dimensions, fit mode,
  sampling, and rounded clipping are copied into the bounded queue and replayed
  through the same immediate image policy. Generation-bound variants retain only
  a logical resource slot/generation, repair stale binding indexes with bounded
  scans, and skip disposed generations without retaining a native image pointer.
  Direct generation-bound image commands are available when a control already
  has its final destination rectangle.
- Skia source-crop drawing is also Elisa-owned: immediate and deferred image
  commands carry a bounded pixel-space source rectangle plus a logical
  destination rectangle, while the native bridge only forwards those sanitized
  rectangles to `SkCanvas::drawImageRect`. Generation-bound crop helpers retain
  only `(slot,generation)` resource identity through deferred replay. Rounded
  crop variants compose the same source rectangle with the bounded Elisa clip
  ledger for immediate and deferred thumbnails.
- Skia shadow color is now an explicit Elisa `Color` on the additive bridge;
  the original black-only symbol remains a compatibility wrapper for older
  hosts, while framework rendering no longer relies on a native appearance
  default. Deferred shadows carry the same color record through the bounded
  queue, keeping immediate and callback-time custom effects equivalent.
- The optional AppKit/Skia compositor in
  `src/platform/appkit/appkit_skia_host.cpp` is linked only by the Skia canvas
  product; the standard AppKit product keeps its CoreGraphics fallback.

The two Objective-C files total 1,507 lines, but the custom canvas shim has no
framework state table, widget/layout traversal, rendering path, text policy,
semantic diff, selector map, menu schema, clipboard policy, or headless mode.
Those decisions are made in Elisa and cross the boundary as typed values or
opaque handles. The custom canvas window title is also assigned from Elisa
after construction through a dedicated setter, so the constructor itself only
creates native objects and attaches the required protocols. Remaining native
code is required to message Cocoa objects or implement Cocoa protocols. Redraw
timers retain only an opaque window handle and re-enter Elisa for lifecycle
validation before a redraw. The category-by-category audit is recorded in
[`docs/native-boundary.md`](native-boundary.md), and
`scripts/check_appkit_canvas.sh` contains source guards for the ownership
decisions.

Tracked Elisa file lengths at this baseline include the custom canvas facade
(`ui_appkit_canvas.elisa`, 14 lines), whose native, retained-state,
accessibility, input, render, window, and callback modules are all below 400
lines; the ready-to-use flat adapter is 321 lines (with text-command routing
isolated in `ui_appkit_canvas_text.elisa`, 90 lines). The clipboard cache and
transient text buffers are isolated in `ui_appkit_canvas_clipboard.elisa`, 66
lines. The retained native-control arena (`ui_controls.elisa`) is 290 lines;
its widget-to-control policy is isolated in `ui_controls_policy.elisa`, 102
lines. Together they own bounded caption storage and native-control state.
The flat widget compatibility
facade (`ui_widget.elisa`, 28 lines) now delegates to cohesive state, layout,
input, focus, style, callback, text, scrolling, and painting modules, each below
400 lines. The layout implementation is kept in `ui_flat_layout.elisa` (320
lines), with keyboard focus/capture policy in `ui_flat_focus.elisa`, text
semantic projection and focus visibility in `ui_flat_text_semantics.elisa`, visual
color policy in `ui_flat_style.elisa`, shared `UiTheme` palette adaptation in
`ui_flat_theme.elisa` (37 lines), the shared Unicode property tables in the
small `ui_text_grapheme_props_*.elisa` modules and boundary walker in
`ui_text_grapheme.elisa` (149 lines), and legacy callback lowering in
`ui_flat_events.elisa`. The flat editor and line planner both use that single
UiText-owned walker, so wrapping cannot split a combining or ZWJ cluster. The
frame-local line-height cache in `ui_text_metrics.elisa` keeps repeated widget
painting metrics in Elisa while resetting at each paint boundary. The AppKit
canvas flat adapter keeps its externally
mandated export declarations in `ui_appkit_canvas_flat_exports.elisa`, separate
from callback policy. The AppKit controls backend is
now split into realization/policy (`ui_appkit.elisa`, 306 lines), typed native
bridge wrappers (`ui_appkit_native.elisa`, 212 lines), ABI declarations
(`ui_appkit_native_ffi.elisa`, 75 lines), and read-back inspection wrappers
(`ui_appkit_native_inspection.elisa`, 121 lines). The SDL3 backend
is split into lifecycle/state (`ui_sdl3.elisa`, 335 lines), event-union
decoding (`ui_sdl3_events.elisa`, 145 lines), run-loop policy
(`ui_sdl3_run.elisa`, 139 lines), and drawing/font state
(`ui_sdl3_draw.elisa`, 265 lines). New or changed Elisa source continues
to use small, single-purpose modules; the existing large modules are
not split mechanically.

`UiMetrics` keeps its frame-stage facade small and isolates independent
layout/text/resource timing scopes in `ui_metrics_work.elisa` (148 lines),
so diagnostics can grow without enlarging the frame-state module.

The remote facade (`ui_remote.elisa`) is a 10-line include surface over typed
offer/selection records, pure presentation and scale negotiation, and session
lifecycle/input-acknowledgement state. The transport host still owns sockets,
packets, and video/framebuffer objects; `UiRemote` exposes only bounded,
inspectable policy facts to the retained framework.

The modal and navigation input policy remains in the shared `UiBack` module
over `UiDialog` (305 lines) and `UiNavigation`. Their public tokens are
module-specific (`DialogHandle`, `NavigationHandle`), as are resource tokens
(`ResourceHandle`); identity queries use explicit `dialog_*`, `navigation_*`,
and `resource_*` names so the current compiler cannot confuse included module
records or helper bodies. AppKit canvas callbacks (255
lines), SDL3 event delivery, and the WasmBrowser dispatcher (45 lines) translate
Escape into that shared policy before invoking application code; modal dialogs
take precedence, followed by application-owned consume/confirm/navigation
decisions, and only an unhandled fact reaches the host close action. Dialog and
navigation private state uses module-unique names because Elisa's current
compiler resolves colliding private globals across included modules. The
`scripts/check_global_names.sh` gate now rejects duplicate mutable module-global
names across the source tree, covering all backend and test include graphs.

The core and widget operation facades follow the same boundary: `ui_core.elisa`
is a 12-line include surface over typed, frame, accessibility, geometry, event,
and retained state modules; the frame implementation is now 312 lines and the
semantic-node builder is 94 lines, with semantic diff/relationship queries in
`ui_core_semantics.elisa`. `ui_ops.elisa` is a 10-line include surface over query,
layout, scrolling, hit, paint, and pointer modules. The WasmBrowser adapter is
now an example of the intended refactoring boundary:
`ui_wasmbrowser.elisa` contains the host-facing declarations and WIT export
glue (302 lines), while `ui_wasmbrowser_runtime.elisa` contains the private
frame/event/wire implementation (302 lines). The split preserves the required
top-level export symbols and keeps the internal painter and encoder names
module-private.
