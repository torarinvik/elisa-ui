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
| UI-00 | implemented-tested | `docs/implementation-baseline*`; `check_toolchain.sh`, `check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh` | none |
| UI-01 | implemented-tested | `UiHandles` builders/stale checks, compatibility entrypoints, generated SDK host bindings; hello builds native and `.wapp` (`build_native.sh`, `check_wapp.sh`) | none |
| UI-02 | implemented-tested | `UiLifecycle`, `UiState`, `UiTasks`, `UiEvents`, `UiHarness`; idle wait in `sdl3_wait_event_test`/`sdl3_lifecycle_stop_test` | none |
| UI-03 | implemented-tested (portable) | `UiCore` commands, `UiRaster`, `UiPaint`, images/gradients/rounded/shadows, text pipeline, `UiTextMetrics` cache, geometry validation; `skia_painter_test`; SDL render targets/device reset and device-loss renderer recreation (`sdl3_device_loss_test`) | real-Skia raster gate needs the pinned SDK; color space is sRGB-only |
| UI-04 | implemented-tested (portable + iOS/Android backends) | `UiResponsive`, `UiMobileSurface`, `UiNavigation`, `UiServices`; `check_uikit.sh`, `check_uikit_simulator.sh`, `check_uikit_touch.sh`; Android gate exists | native permission/picker adapters; Android re-verify needs SDK/NDK/emulator |
| UI-05 | implemented-tested | key/text/IME/focus/gesture/secure policy; `UiShortcuts`; word navigation; `unicode_conformance_test` (1187 rows) | hosted Alt key-code is a WasmBrowser WIT gap (WB-05) |
| UI-06 | implemented-tested (portable + AppKit/UIKit) | `UiCore` semantics incl. Image/Group/List/Status/Alert; `accessibility_metadata_test`, `accessibility_geometry_test`; AppKit/UIKit adapters | hosted semantics has no WasmBrowser host channel (WB-05); real screen-reader device runs not verified here |
| UI-07 | implemented-tested (partial) | sizer/layout corpus, `UiConstraints`, `UiTheme`, `UiLocalization`, `UiValidation`, `UiIdentity`, `UiVirtualList` geometry + bounded realization/slot reuse, `UiTable` column layout | tree control and third-party control groups |
| UI-08 | implemented-elisa-boundary | `UiResources` state machine, `UiResourcePresentation`, network/decode progress, demand/prefetch, intrinsic geometry | SDK/host transport integration |
| UI-09 | implemented-elisa-boundary | `UiFeatureView` lifecycle, tokens, retry, owner disposal | SDK/host component activation |
| UI-10 | implemented-tested (partial) | `UiInspector` hierarchy/bounds/dirty/focus/semantics/timings; `UiHarness`; release packaging; per-build toolchain display | SDK log/source-location integration |
| UI-11 | implemented-elisa-boundary | `UiRemote` negotiation/lifecycle/acknowledgement/limitations | WasmBrowser/SDK transport adapter |
| UI-12 | implemented-tested (C/C++/Rust) | `elisa_ui.h`, C host + C++17 header check, header↔symbol cross-check in `check_capi.sh`, bound ABI version, safe Rust wrapper + example (`check_rust.sh`) | Go bindings |
| UI-13 | implemented-tested (partial) | `UiBuild` version + compatibility; backend matrix; `check_performance.sh`; `package_release.sh` with LICENSE/integrity | reference-device budgets, GPU upload, idle-CPU, energy measurements |

The first implementation batch (plan §21) is satisfied: UI-00 is complete, the
public backend/API map consumes pinned SDK bindings, the hello reference screen
covers persistence/text/resource errors, and it runs on the hosted profile and
native backends. Mobile execution proceeds through the iOS/Android gates above.
