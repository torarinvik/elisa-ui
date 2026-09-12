# Decision records

_Companion to [implementation-baseline.md](../implementation-baseline.md)._

The plan names decisions that need an explicit experiment rather than a guess.
Each record below states the question, owner, prototype, supported compiler,
acceptance fixture, result, selected approach, and migration effect. Records
whose experiment still needs an external fixture say so and stay open.

## D-1 Higher-level Elisa UI API shape

- **Question** — declarative language, retained builder API, or both?
- **Owner** — elisa-ui; input from application authors.
- **Prototype** — `UiHandles` typed builders over the retained tree; the shared
  `examples/hello` app across native, AppKit canvas, and hosted entrypoints.
- **Compiler** — pinned stage1 (`986a30b9d6a1` at this baseline).
- **Acceptance fixture** — `test/widget_handles_test.elisa`,
  `test/widget_dispatch_test.elisa`, `build_native.sh`, `check_wapp.sh`.
- **Result** — the same module runs on every backend with no raw ABI code; the
  older index API still compiles.
- **Selected approach** — module-qualified builder API, no new declarative
  language or compiler prerequisite. Low-level handles remain for adapters.
- **Migration effect** — additive: `UiFlat` index API is retained as documented
  compatibility; `UiHandles::index` is the one explicit escape hatch.

## D-2 Text/shaping authority by backend

- **Question** — does one shaper own metrics for every profile, or does each
  profile shape locally?
- **Owner** — elisa-ui.
- **Prototype** — `UiTextMetrics` frame cache keyed by font/scale generation;
  `UiTextMeasureLayout` with a backend width provider; SDL_ttf, CoreText, and
  the hosted `measure-text-width` host call.
- **Compiler** — pinned stage1.
- **Acceptance fixture** — `test/sdl3_text_test.elisa`,
  `test/text_metrics_cache_test.elisa`, `test/text_layout_test.elisa`,
  `scripts/check_unicode_conformance.sh` (1187 UAX #29 rows).
- **Result** — metrics differ by backend exactly as the plan predicted; layout
  and grapheme policy are shared and backend-neutral.
- **Selected approach** — per-profile text authority. Shape/layout locally with
  known fonts; host measure-text-width when hosted. Never assume SDL_ttf,
  CoreText, and the host agree.
- **Migration effect** — none for applications; backends must supply their own
  width provider and bump the metric generation on font/scale change.

## D-3 GPU fallback profile

- **Question** — require a GPU path, or keep an explicit CPU fallback?
- **Owner** — elisa-ui.
- **Prototype** — `UiSkia` narrow FFI (CPU raster) behind a pinned
  `third_party/skia.lock`; CoreGraphics fallback on the AppKit canvas; SDL
  software renderer; hosted six-command protocol.
- **Compiler** — pinned stage1; Skia `chrome/m150`.
- **Acceptance fixture** — `test/skia_painter_test.elisa`,
  `test/skia_offscreen_host.cpp`, `scripts/check_appkit_skia.sh`.
- **Result** — CPU raster is reproducible and gated; GPU/Metal remains optional
  and is not claimed without a host surface.
- **Selected approach** — six-command portable protocol, Skia when a host
  supplies the pinned canvas, CoreGraphics/SDL fallbacks otherwise. Arbitrary
  new GPU features are not assumed serializable through six commands.
- **Migration effect** — additive bridge with a packed Skia ABI version.

## D-4 Mobile native/hosted support split

- **Question** — native mobile backends, hosted WasmBrowser, or both?
- **Owner** — elisa-ui with WB-03.
- **Prototype** — native UIKit canvas/controls, Android Skia canvas/controls,
  and the portable `UiMobileSurface` fact contract.
- **Compiler** — pinned stage1.
- **Acceptance fixture** — `test/mobile_surface_test.elisa`,
  `scripts/check_uikit.sh`, `check_uikit_simulator.sh`, `check_uikit_touch.sh`,
  `check_android.sh`.
- **Result** — native mobile is implemented-tested (simulator/device gates);
  hosted mobile still needs the WasmBrowser device fixture.
- **Selected approach** — one mobile primary surface, native first; hosted
  mobile is a separate WB milestone rather than assumed parity.
- **Migration effect** — none; `UiMobileSurface` is additive.

## D-5 Feature-view isolation

- **Question** — can a loaded feature own its surface, or must it return data
  to a parent-owned view?
- **Owner** — elisa-ui with SDK-08/WB-09.
- **Prototype** — `UiFeatureView` activation state machine over host tokens.
- **Compiler** — pinned stage1.
- **Acceptance fixture** — `test/feature_view_test.elisa`.
- **Result** — the Elisa boundary is tested; actual component activation and
  memory ownership are host/SDK.
- **Selected approach** — bounded host/application-mediated interface. The SDK
  owns identity, verification, and activation; the UI owns only typed view
  state. No UI downloader, linker, or raw pointer exchange.
- **Migration effect** — none; optional path.

## D-6 Stable C/component interop ownership

- **Question** — one canonical ABI, with the SDK-generated bindings consumed by
  the framework, or a duplicated hand-written layer?
- **Owner** — elisa-ui with SDK-00/WB-00.
- **Prototype** — versioned `include/elisa_ui.h` plus `src/capi/`; the hosted
  adapter consumes generated SDK bindings from the staged `sdk/` root.
- **Compiler** — pinned stage1.
- **Acceptance fixture** — `scripts/check_capi.sh` (header↔symbol both ways),
  `scripts/check_rust.sh`, `scripts/check_wapp.sh`.
- **Result** — the C ABI is versioned and cross-checked; the component path uses
  SDK bindings rather than a second canonical implementation.
- **Selected approach** — C ABI owned here for native/foreign hosts; component
  interop consumes the authoritative SDK bindings. Ownership migration goes
  through SDK-00/WB-00, not a shortcut.
- **Migration effect** — packed ABI version gates foreign hosts; minor/patch
  changes preserve wire records.
