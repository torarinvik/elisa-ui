# elisa-ui implementation baseline

Recorded 2026-09-05 on macOS arm64. This is the durable UI-00 audit for the
local implementation plan; it records observed behavior, not an assumption of
parity on untested platforms.

## Reproducibility tuple

| Item | Observed value |
| --- | --- |
| elisa-ui revision | `bb876df` on branch `work` |
| Host | Darwin 25.6.0, arm64 (`Torarins-MacBook-Air.local`) |
| C compiler | Homebrew clang 23.1.0 |
| Elisa compiler | `../elisa-ui-worktrees/stage1/bin/elisac-stage1`; SHA-256 `dca7d0851ecf6faaa46021db206c1b08e391dc14ecd037b467d2679381d946c3` |
| Elisa runtime | `../elisa-ui-worktrees/stage1/build/runtime/elisacore_runtime.o` |
| WasmBrowser checkout | revision `24fa9d6` |
| WasmBrowser WIT | `../WasmBrowser/wit/wasmbrowser.wit`; SHA-256 `fa165611fe4934cc9508bc435a7a396bc9d203225aa2a510f6d35ae74ec12172` |
| wasm-sdk checkout | revision `7f71963` (standalone SDK work is in progress) |
| Rust component linker | rustc 1.98.0; `wasm-component-ld` from the stable aarch64 toolchain |
| Native libraries | Homebrew SDL3 3.4.14 and SDL_ttf 3.2.2 under `/opt/homebrew/lib` |

The working tree also contains an unrelated user edit to
`examples/hello/manifest.json`; it is intentionally not part of this baseline
commit.

## Source and boundary inventory

Public framework modules are `UiCore`, `UiPaint`, `UiRaster`, `UiConst`,
`UiWidgets`, `UiFlat`, `UiHandles`, `UiControls`, `UiCapi`, `UiAppKit`,
`UiAppKitCanvas`, `UiSdl3`, and `UiWasmBrowser`. The application contract is
the top-level `app_init`, `app_event`, `app_text_input`, `app_text_editing`,
`app_frame`, and optional `app_widget_event` callbacks.

Externally imposed symbols are kept at the edges:

- C ABI declarations and exports in `include/elisa_ui.h` and `src/capi/`.
- SDL3/SDL_ttf C functions in `src/platform/sdl3/ui_sdl3.elisa`.
- CoreGraphics, CoreText, CoreFoundation, ImageIO, libobjc, and AppKit fact
  globals in `src/platform/appkit/ui_appkit_canvas.elisa`.
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
retained widget module (`ui_widget.elisa`, 2,812 lines) and custom canvas
adapter (`ui_appkit_canvas.elisa`, 1,729 lines). New or changed Elisa source
continues to use small, single-purpose modules; the existing large modules are
not split mechanically.

## Backend and feature matrix

| Backend/profile | Status | Evidence or limitation |
| --- | --- | --- |
| SDL3 native | implemented-tested | `scripts/run_tests.sh`; SDL keymap/text tests and dummy-video smoke path pass. |
| AppKit native controls | implemented-tested | `scripts/check_appkit.sh` creates and reads real NSWindow/NSView/control objects without ordering a window onscreen. |
| AppKit custom canvas | implemented-tested | `scripts/check_appkit_canvas.sh` builds/signs the app, renders an off-screen PNG, and exercises semantic-object identity and callbacks. |
| WasmBrowser hosted | implemented-unverified / blocked | Source and WIT exports exist, but the current component link is rejected by the compiler output defect below. |
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
  sdl3 keymap/text, widget dispatch, widget handles, widget layout: PASS
git diff --check: PASS
```

The AppKit checks use activation policy prohibited and the custom canvas smoke
path; no window is shown or foregrounded. The hello app's new
`UiFlat::handle` entry point is covered by `test/widget_dispatch_test.elisa`.

`bash scripts/build_wapp.sh hello` currently fails before packaging:

```text
failed to encode component
type mismatch: expected i64, found i32 (at offset 0x2b06)
```

This is recorded as a compiler/toolchain blocker, not a framework feature
failure. The raw module contains a malformed generated comparison in
`UiCore.draw`; the strict `wasm-component-ld --validate-component=true` check
rejects it. Minimal WIT probes validate independently, so the next Wasm task
must isolate or fix that compiler defect before claiming hosted parity.

## Ownership decisions and next gaps

- Elisa owns retained widget/resource-visible state, layout, interaction,
  themes, semantic generation, text editing, frame scheduling decisions, and
  application-visible errors.
- Native/host hosts own OS objects, event queues, text shaping/rasterization,
  GPU/image mechanisms, accessibility protocol objects, package delivery, and
  service authority. Shims pass raw facts and explicit framework decisions.
- The hosted backend still contains handwritten WIT/canonical ABI declarations;
  it should consume the authoritative SDK-generated bindings after the SDK/WIT
  migration gate, without creating a second ABI implementation.
- The next concrete work items are a compiler-independent hosted build fixture,
  lifecycle/reentrancy tests around the new typed event router, and a public
  builder layer over `UiHandles`. Android/iOS and remote work remain blocked on
  sibling host/SDK execution fixtures rather than being simulated here.
