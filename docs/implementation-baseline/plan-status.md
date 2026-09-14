# Workstream status and evidence

_Companion to [implementation-baseline.md](../implementation-baseline.md)._

This maps each workstream in the local implementation plan to its current
evidence and any external blocker. Statuses mean:

- **implemented-tested** — a fixture, gate, or build in this repo exercises it.
- **implemented-elisa-boundary** — the portable Elisa policy is tested, but the
  native/host adapter is a separate integration owned with the sibling repos.
- **blocked-external** — needs a WasmBrowser/SDK/device change this repo cannot
  make without private host access.
- **not-implemented** — no code yet; a real remaining gap.

| ID | Status | Evidence | Remaining blocker |
| --- | --- | --- | --- |
| UI-00 | implemented-tested (refreshed 2026-09-15) | `docs/implementation-baseline*`; latest compiler tuple; `check_toolchain.sh`, `check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh`; required optimized Showcase Skia gate | complete cross-platform `run_tests.sh` matrix still has reported linker/SDK blockers; shared compiler checkout has unfinished edits, so use a clean build of the same latest revision |
| UI-01 | implemented-tested (native; hosted build pending) | `UiHandles` builders/stale checks, compatibility entrypoints, generated SDK host bindings; native hello and `.wapp` build gate | `.wapp` verification needs `wasm-component-ld` on PATH; it is absent on this host |
| UI-02 | implemented-tested | `UiLifecycle`, `UiState`, `UiTasks`, `UiEvents`, `UiHarness`; `lifecycle_test` covers both pause/surface-loss orderings and proves focus/resume stay non-renderable until surface restoration; idle wait in `sdl3_wait_event_test`/`sdl3_lifecycle_stop_test` | none |
| UI-03 | implemented-tested (portable + real CPU-raster Skia) | `UiCore` commands, `UiRaster`, `UiPaint`, images/gradients/rounded/shadows, text pipeline, `UiTextMetrics` cache, geometry validation; pinned `check_skia.sh` semantic-enabled fresh-process pixel digests and all showcase page/state PNGs; off-screen AppKit/Skia compositor; SDL device-loss fixture | color space is sRGB-only; GPU surface/device-loss parity and other color-space behavior remain unverified |
| UI-04 | implemented-tested (portable + iOS/Android backends) | `UiResponsive`, `UiMobileSurface`, `UiNavigation`, `UiServices`; shared counted UTF-8/UTF-16 codec gate; `check_uikit.sh`, `check_uikit_simulator.sh`, `check_uikit_touch.sh` | native permission/picker adapters; Android app/device IME gate not rerun in this refresh |
| UI-05 | implemented-tested (portable; hosted/device edges remain) | key/text/IME/focus/gesture/secure policy; `UiShortcuts`; word navigation; pinned Unicode corpus (1187 rows); `text_lifecycle_workflow_test` covers typed-handle editing, stale async validation, resource-triggered relayout, blur, teardown, and invalidation when identical programmatic replacement clears IME state; Android composition ranges now use the UTF-16 API directly | hosted Alt key-code is a WasmBrowser WIT gap (WB-05); physical-device IME/accessibility paths remain separate acceptance work |
| UI-06 | implemented-tested (portable + AppKit/UIKit) | `UiCore` semantics incl. Image/Group/List/Status/Alert and typed collection count/position; `accessibility_metadata_test`, `accessibility_geometry_test`; AppKit/UIKit semantic-layout invalidation tests | hosted semantics has no WasmBrowser host channel (WB-05); native row-index/total mapping and physical screen-reader runs remain unverified |
| UI-07 | implemented-tested (partial) | sizer/layout corpus, `UiConstraints`, `UiTheme`, `UiLocalization`, `UiValidation`, `UiIdentity`, `UiVirtualList` geometry and bounded realization; `UiHandles::virtual_list` connects logical anchors to retained layout, wheel input, scrollbar drag, row recycling, typed position/count semantics and stale-press protection; the real Skia Showcase loads, scrolls to, selects, hides and restores item 1,000,000 without growing the widget tree, then verifies identical tail-frame pixels in fresh processes; M5 benchmark retains the policy-window workload | AppKit list/row proxies and UIKit lazy logical-row container; variable-height/horizontal virtualization; hosted collection mapping; budgets on other reference devices |
| UI-08 | implemented-elisa-boundary | `UiResources` state machine and `UiResourcePresentation`; `resource_state_test` covers coalesced multi-owner leases, owner-scoped cancellation/disposal, aggregate visibility priority, and generation reuse; `resource_presentation_test` covers owner-preserving presentation/demand; SDL3 public showcase image workflow verifies real retained pixels | SDK/host transport integration |
| UI-09 | implemented-elisa-boundary | `UiFeatureView` coalesced owner leases, per-owner cancellation/disposal, token-safe deactivation tombstones, stale polling, and retry generations in `feature_view_test` | SDK/host component activation integration |
| UI-10 | implemented-tested (partial) | `UiInspector` hierarchy/bounds/dirty/focus/semantics/timings; `UiHarness`; release packaging; per-build toolchain display | SDK log/source-location integration |
| UI-11 | implemented-elisa-boundary | `UiRemote` negotiation/lifecycle/acknowledgement/limitations | WasmBrowser/SDK transport adapter |
| UI-12 | implemented-tested (C/C++/Rust) | `elisa_ui.h`, C host + C++17 header check, header↔symbol cross-check in `check_capi.sh`, bound ABI version, safe Rust wrapper + example (`check_rust.sh`) | Go bindings |
| UI-13 | implemented-tested (partial) | `UiBuild` version + compatibility; backend matrix; `run_tests.sh` requires `check_performance.sh`'s exact-tuple policy budget; required optimized real-Skia gate measures the public million-item Showcase workflow plus tail rendering over 21 samples, checks stable pixels, and enforces an exact host/compiler/Skia/source tuple in `test/showcase_skia_performance_budgets.json`; `test/performance_budgets.json` retains portable workload raw samples; `test/stress_test.elisa`; release packaging and guides | budgets on other reference devices, GPU upload, idle CPU, energy, and broader mobile-device performance |

The first implementation batch (plan §21) is partially evidenced: the public
backend/API map consumes pinned SDK bindings, and the hello reference screen
covers persistence, text, and resource errors on native backends. Current hosted
package verification is blocked until `wasm-component-ld` is available. Mobile
execution proceeds through the iOS/Android gates above.
