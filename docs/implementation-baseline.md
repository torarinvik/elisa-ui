# elisa-ui implementation baseline

Recorded 2026-09-05 on macOS arm64. This is the durable UI-00 audit for the
local implementation plan; it records observed behavior, not an assumption of
parity on untested platforms.

## Reproducibility tuple

| Item | Observed value |
| --- | --- |
| elisa-ui revision | `b5d84b7` on branch `work` |
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

Public framework modules are `UiCore`, `UiPaint`, `UiRaster`, `UiConst`,
`UiWidgets`, `UiFlat`, `UiHandles`, `UiControls`, `UiCapi`, `UiAppKit`,
`UiAppKitNative`, `UiAppKitCanvas`, `UiSdl3`, `UiSdl3Draw`, and
`UiWasmBrowser`, and `UiInspector`. The application contract is
the top-level `app_init`, `app_event`, `app_text_input`, `app_text_editing`,
`app_frame`, and optional `app_widget_event` callbacks.

Externally imposed symbols are kept at the edges:

- C ABI declarations and exports in `include/elisa_ui.h` and `src/capi/`.
- SDL3/SDL_ttf C functions in `src/platform/sdl3/ui_sdl3.elisa`; the
  `UiSdl3Draw` module in `src/platform/sdl3/ui_sdl3_draw.elisa` owns renderer,
  font, raster, and painter state behind that boundary.
- CoreGraphics, CoreText, CoreFoundation, ImageIO, libobjc, and AppKit fact
  globals in `src/platform/appkit/ui_appkit_canvas.elisa`; typed controls bridge
  wrappers in `src/platform/appkit/ui_appkit_native.elisa`.
- WasmBrowser WIT imports/exports and canonical record encoding in
  `src/platform/wasmbrowser/ui_wasmbrowser.elisa`.
- Cocoa object/protocol/selector entry points in
  `src/platform/appkit/appkit_shim.m` and `appkit_canvas_shim.m`.

The two Objective-C files total 1,298 lines, but the custom canvas shim has no
framework state table, widget/layout traversal, rendering path, text policy,
semantic diff, selector map, menu schema, clipboard policy, or headless mode.
Those decisions are made in Elisa and cross the boundary as typed values or
opaque handles. Remaining native code is required to message Cocoa objects or
implement Cocoa protocols; `scripts/check_appkit_canvas.sh` contains source
guards for the ownership decisions.

Tracked Elisa file lengths at this baseline include the intentionally cohesive
retained widget module (`ui_widget.elisa`, 2,888 lines) and custom canvas
adapter (`ui_appkit_canvas.elisa`, 1,729 lines). The AppKit controls backend is
now split into realization/policy (`ui_appkit.elisa`, 288 lines) and typed
native bridge wrappers (`ui_appkit_native.elisa`, 370 lines). The SDL3 backend
is split into lifecycle/event (`ui_sdl3.elisa`, 392 lines) and drawing/font
state (`ui_sdl3_draw.elisa`, 228 lines). New or changed Elisa source continues
to use small, single-purpose modules; the existing large modules are
not split mechanically.

The WasmBrowser adapter is now an example of the intended refactoring boundary:
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
  widget inspector, widget reentrancy, ui harness, core invalidation: PASS
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
  themes, semantic generation, text editing, frame scheduling decisions, and
  application-visible errors.
- Native/host hosts own OS objects, event queues, text shaping/rasterization,
  GPU/image mechanisms, accessibility protocol objects, package delivery, and
  service authority. Shims pass raw facts and explicit framework decisions.
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
- `UiInspector` is a read-only, allocation-free diagnostic projection of the
  retained tree and semantic buffer. It reports deferred layout/frame-buffer
  state and typed relationships while redacting secure text; coverage lives in
  `test/widget_inspector_test.elisa`.
- `UiHarness` is the deterministic Elisa-side test driver. It injects a
  monotonic clock, typed lifecycle/input events, and frame boundaries while
  leaving production event-loop ownership with each backend; coverage lives in
  `test/ui_harness_test.elisa`.
- `UiCore::Invalidation` is the shared dirty model for layout, paint, semantics,
  resources, and animation scheduling. Frame-local reasons clear at
  `begin_frame`, while layout/resource reasons remain until an owner resolves
  them; `UiInspector::Frame` exposes the five states and
  `test/core_invalidation_test.elisa` covers the lifecycle.
- `scripts/check_wapp.sh` is now the compiler-independent hosted package
  fixture: it inspects an existing `.wapp` through WasmBrowser's CLI and
  asserts the profile, host imports, guest exports, and absence of JS/TS/ESM
  artifacts. The public `UiHandles` builder covers all flat constructors,
  typed state setters/queries, event forwarding, hit testing, accessibility
  actions, and text editing with stale-handle guards. Android/iOS and remote
  work remain blocked on sibling host/SDK execution fixtures rather than being
  simulated here; the next UI-side integration gap is consuming generated
  SDK bindings instead of the hosted adapter's handwritten WIT lowering.
