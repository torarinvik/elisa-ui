# elisa-ui implementation baseline

Recorded 2026-09-05 on macOS arm64. This is the durable UI-00 audit for the
local implementation plan; it records observed behavior, not an assumption of
parity on untested platforms.

## Reproducibility tuple

| Item | Observed value |
| --- | --- |
| elisa-ui revision | `ee02040` on branch `work` |
| Host | Darwin 25.6.0, arm64 (`Torarins-MacBook-Air.local`) |
| C compiler | Homebrew clang 23.1.0 |
| Elisa compiler | `../wasm-sdk-compiler/bin/elisac-stage1` on `codex/wasm-sdk`, revision `1a44c1d1`; SHA-256 `a9573ad3779ae57f9daf68f79c53761c5ec54d0045a11c1387071ba0562678bc` |
| Elisa runtime | `../wasm-sdk-compiler/build/runtime/elisacore_runtime.o`; SHA-256 `cb06532f0c37540284de4ceaa622d0da9193f113877ac391fb00bad4bf9ff1e9` |
| WasmBrowser checkout | revision `2bb3d5f` (host worktree has unrelated local `.gitignore` edits) |
| WasmBrowser WIT | `../WasmBrowser/wit/wasmbrowser.wit`; SHA-256 `fa165611fe4934cc9508bc435a7a396bc9d203225aa2a510f6d35ae74ec12172` |
| wasm-sdk checkout | revision `820fee2` (standalone SDK contract provenance and package validation) |
| Rust component linker | rustc 1.98.0; `wasm-component-ld` from the stable aarch64 toolchain |
| Native libraries | Homebrew SDL3 3.4.14 and SDL_ttf 3.2.2 under `/opt/homebrew/lib` |

The hello manifest now declares the versioned `wasmbrowser:component@1`
profile, Elisa language, and elisa-ui framework explicitly.

## Source and boundary inventory

Public framework modules are `UiCore`, `UiLifecycle`, `UiMetrics`, `UiState`, `UiCapabilities`, `UiEvents`, `UiPaint`, `UiRaster`,
`UiConst`, `UiWidgets`, `UiFlat`, `UiHandles`, `UiResources`, `UiResourcePresentation`,
`UiControls`, `UiCapi`, `UiAppKit`, `UiAppKitNative`, `UiAppKitCanvas`, `UiSdl3`,
`UiSdl3Draw`, `UiWasmBrowser`, and `UiInspector`. The application contract is
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
- WasmBrowser WIT imports/exports and canonical record encoding in
  `src/platform/wasmbrowser/ui_wasmbrowser.elisa`.
- Cocoa object/protocol/selector entry points in
  `src/platform/appkit/appkit_shim.m` and `appkit_canvas_shim.m`.

The two Objective-C files total 1,277 lines, but the custom canvas shim has no
framework state table, widget/layout traversal, rendering path, text policy,
semantic diff, selector map, menu schema, clipboard policy, or headless mode.
Those decisions are made in Elisa and cross the boundary as typed values or
opaque handles. Remaining native code is required to message Cocoa objects or
implement Cocoa protocols; the category-by-category audit is recorded in
[`docs/native-boundary.md`](native-boundary.md), and
`scripts/check_appkit_canvas.sh` contains source guards for the ownership
decisions.

Tracked Elisa file lengths at this baseline include the custom canvas facade
(`ui_appkit_canvas.elisa`, 12 lines), whose native, retained-state,
accessibility, input, render, window, and callback modules are all below 400
lines; the ready-to-use flat adapter is 393 lines. The flat widget compatibility
facade (`ui_widget.elisa`, 22 lines) now delegates to cohesive state, layout,
input, text, scrolling, and painting modules, each below 400 lines. The AppKit controls backend is
now split into realization/policy (`ui_appkit.elisa`, 288 lines) and typed
native bridge wrappers (`ui_appkit_native.elisa`, 370 lines). The SDL3 backend
is split into lifecycle/event (`ui_sdl3.elisa`, 392 lines) and drawing/font
state (`ui_sdl3_draw.elisa`, 228 lines). New or changed Elisa source continues
to use small, single-purpose modules; the existing large modules are
not split mechanically.

The core and widget operation facades follow the same boundary: `ui_core.elisa`
is an 8-line include surface over typed, frame, geometry, event, and retained
state modules, and `ui_ops.elisa` is a 10-line include surface over query,
layout, scrolling, hit, paint, and pointer modules. The WasmBrowser adapter is
now an example of the intended refactoring boundary:
`ui_wasmbrowser.elisa` contains the host-facing declarations and WIT export
glue (300 lines), while `ui_wasmbrowser_runtime.elisa` contains the private
frame/event/wire implementation (252 lines). The split preserves the required
top-level export symbols and keeps the internal painter and encoder names
module-private.

## Backend and feature matrix

| Backend/profile | Status | Evidence or limitation |
| --- | --- | --- |
| SDL3 native | implemented-tested | `scripts/run_tests.sh`; SDL keymap/text tests and dummy-video smoke path pass. |
| AppKit native controls | implemented-tested | `scripts/check_appkit.sh` creates and reads real NSWindow/NSView/control objects without ordering a window onscreen. |
| AppKit custom canvas | implemented-tested | `scripts/check_appkit_canvas.sh` builds/signs the app, renders an off-screen PNG, and exercises semantic-object identity and callbacks. |
| WasmBrowser hosted | implemented-tested for build/package/inspect | The synchronized compiler, explicit `Host` permission family, and component-memory sizing produce `build/hello.wapp`; WasmBrowser inspect reports the expected profile and imports/exports. Runtime launch and device execution still need dedicated fixtures. |
| Android standalone | planned | No Android build or device fixture exists in this checkout. |
| iOS standalone | planned | No iOS build or device fixture exists in this checkout. |
| Remote rendering/input | planned | Capability negotiation belongs to WasmBrowser/SDK; no elisa-ui remote fixture exists yet. |

Implemented-tested in the current native corpus: retained layout and dirty
relayout, typed widget lifetimes, hit testing and scrolling, control state,
Unicode text editing/IME and bounded undo history, themes, clipping and raster
commands, C API shape, AppKit semantics, and SDL/AppKit key maps. Implemented
but not yet device-verified: actual VoiceOver interaction, non-ASCII IMEs on a
physical device, and cross-scale font fallback. Secure text is intentionally
excluded from readback, semantic selected text, snapshots, and clipboard.

Known backend differences are intentional: SDL_ttf and CoreText are separate
font authorities; hosted text is measured by the WasmBrowser host; AppKit
accessibility is native while hosted/mobile adapters still need their own host
fixtures. Clipboard authority is SDL3, AppKit pasteboard, or WasmBrowser's
declared capability respectively, with byte-oriented Elisa adapters above each.

## Current validation

The following completed headlessly from this checkout:

```text
bash scripts/run_tests.sh
  capi, appkit, appkit canvas, appkit canvas keymap, capi bridge,
  controls, drop raii, event wire, hierarchy build/layout, raster,
  sdl3 keymap/text, widget dispatch, widget handles, widget layout,
  widget inspector, widget reentrancy, ui harness, metrics, resource presentation,
  core invalidation, lifecycle: PASS
git diff --check: PASS
```

The hosted packaging gate also passed with the synchronized compiler:

```text
ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/build_wapp.sh hello
wasm-browser inspect build/hello.wapp
  runtime profile: wasmbrowser:component@1
  language: elisa
  framework: elisa-ui
  format: component
```

The shared `examples/hello/app.elisa` now uses `UiHandles::Handle` values for
every retained widget on SDL3, AppKit canvas, and WasmBrowser; only the
backend callback's legacy widget index is converted through the explicit
`UiHandles::index` escape hatch.

The AppKit checks use activation policy prohibited and the custom canvas smoke
path; no window is shown or foregrounded. The hello app's new
`UiFlat::handle` entry point is covered by `test/widget_dispatch_test.elisa`.

The previous hosted blocker (`expected i64, found i32` during component
validation) was resolved for this tuple by consuming the current compiler
work fixes and the component-memory sizing fix from the UI compiler worktree.
The framework now declares its `Host.Present`, `Host.Layout`, and
`Host.Clipboard` permission family explicitly; manifest capabilities remain a
separate host-enforced security boundary.

## Ownership decisions and next gaps

- Elisa owns retained widget/resource-visible state, layout, interaction,
  themes, semantic generation, text editing, frame scheduling decisions,
  lifecycle interpretation, and application-visible errors.
- Native/host hosts own OS objects, native event queues, text
  shaping/rasterization, GPU/image mechanisms, accessibility protocol objects,
  package delivery, and service authority. After translation, `UiEvents` owns
  the bounded Elisa-side FIFO and its overflow policy; shims pass raw facts and
  explicit framework decisions.
- AppKit native-control read-back is routed through the same Elisa-owned,
  autorelease-scoped bridge wrapper surface as construction and mutation; the
  realization module no longer imports raw Cocoa query symbols.
- The hosted backend still contains handwritten WIT/canonical ABI declarations;
  it should consume the authoritative SDK-generated bindings after the SDK/WIT
  migration gate, without creating a second ABI implementation.
- The C boundary now exposes a packed ABI version from Elisa and checks it
  against the public header in `scripts/check_capi.sh`; wire ordinals and field
  meanings remain documented in `include/elisa_ui.h`.
- Callback entry points are lifetime-guarded: if an application handler resets
  the flat tree, post-callback history, composition, activation, adjustment, and
  radio state updates are abandoned instead of touching recycled slots. This is
  covered by `test/widget_reentrancy_test.elisa`.
- `UiFlat` carries the closed `UiConst::WidgetEvent` enum through all control,
  editing, keyboard, and accessibility paths; one private Elisa helper performs
  the final ordinal conversion required by the legacy `app_widget_event` ABI.
- `UiResources` owns bounded logical-resource identity, progress, cancellation,
  retry and generation-safe disposal, including owner-scoped teardown helpers
  and idempotent visibility/prefetch demand priorities. Host/SDK layers still
  own verified bytes, transport, cache and decode/upload authority; resource
  transitions raise the shared resource/paint invalidation reasons and are
  covered by `test/resource_state_test.elisa`.
- `UiResourcePresentation` maps those lifecycle states to explicit
  placeholder/loading/ready/fallback records, reserved geometry, independent
  progress visibility and retry affordances. Kind-specific defaults and all
  presentation decisions remain in Elisa; hosts only resolve verified resource
  data into renderer objects. Coverage lives in
  `test/resource_presentation_test.elisa`.
- `UiInspector` is a read-only, allocation-free diagnostic projection of the
  retained tree and semantic buffer. It reports shared lifecycle phase,
  generation, surface/input/render/focus predicates, deferred layout/frame-
  buffer state, and typed relationships while redacting secure text; coverage
  lives in `test/widget_inspector_test.elisa`.
- `UiMetrics` owns the interpretation of application, semantics, and paint
  stages, monotonic-clock normalization, completion state, retained command and
  semantic counts, overflow flags, and invalidation snapshots. Backends supply
  timestamps from their own clocks; no host-specific timing policy is duplicated
  in the inspector or native bridges. Coverage lives in `test/metrics_test.elisa`.
- `UiState` is the explicit application-state persistence hook. It emits and
  validates a bounded versioned record stream keyed only by application-owned
  numeric IDs; failed restores clear the prior snapshot and no framework
  pointer or arena identity crosses the boundary. Coverage lives in
  `test/ui_state_test.elisa`.
- `UiCapabilities` owns conservative, typed backend profiles. Adapters select a
  profile at startup; applications and `UiInspector` consume capability facts
  without OS-name branches or native-object queries. Coverage lives in
  `test/capabilities_test.elisa`.
- `UiEvents` owns bounded FIFO ingress after each adapter has translated native
  facts into `UiCore::Event`. Synchronous adapters drain immediately; SDL drains
  poll bursts. Full queues reject incoming events and expose sticky loss facts
  through `UiInspector`. Coverage lives in `test/event_queue_test.elisa`.
- AppKit read-back helpers expose only native facts. The button-toggle
  introspection path now performs the native click as one primitive while Elisa
  owns the before/after comparison and state restoration; no test behavior is
  encoded in the Objective-C shim.
- `UiHarness` is the deterministic Elisa-side test driver. It injects a
  monotonic clock, typed lifecycle/input events, resource requests/progress,
  and frame boundaries while leaving production event-loop ownership with each
  backend; `UiLifecycle` centralizes session generations and phase predicates,
  stopping resets resource generations so late completions are ignored; coverage
  lives in `test/ui_harness_test.elisa` and `test/lifecycle_test.elisa`.
- `UiCore::Invalidation` is the shared dirty model for layout, paint, semantics,
  resources, and animation scheduling. Frame-local reasons clear at
  `begin_frame`, while layout/resource reasons remain until an owner resolves
  them; `UiInspector::Frame` exposes the five states and
  `test/core_invalidation_test.elisa` covers the lifecycle.
- `UiCore::frame_timeout_ms` owns deterministic conversion from animation
  seconds to bounded native wait milliseconds. `UiSdl3::animation_timeout` is
  retained only as a compatibility forwarding name; SDL supplies the final
  event-queue call.
- `scripts/check_wapp.sh` is now the compiler-independent hosted package
  fixture: it inspects an existing `.wapp` through WasmBrowser's CLI and
  asserts the profile, host imports, guest exports, and absence of JS/TS/ESM
  artifacts. The public `UiHandles` builder covers all flat constructors,
  typed state setters/queries, event forwarding, hit testing, accessibility
  actions, and text editing with stale-handle guards. The shared hello example
  is migrated to that surface across all three entrypoints. Android/iOS and remote
  work remain blocked on sibling host/SDK execution fixtures rather than being
  simulated here; the next UI-side integration gap is consuming generated
  SDK bindings instead of the hosted adapter's handwritten WIT lowering.
