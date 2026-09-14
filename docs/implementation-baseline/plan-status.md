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
| UI-00 | implemented-tested (refreshed 2026-09-14) | `docs/implementation-baseline*`; latest compiler tuple; `check_toolchain.sh`, `check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh` | observed semantic-enabled compile of the retained Skia unit remained at 99% CPU without output for 72 seconds |
| UI-01 | implemented-tested (native; hosted build pending) | `UiHandles` builders/stale checks, compatibility entrypoints, generated SDK host bindings; native hello and `.wapp` build gate | `.wapp` verification needs `wasm-component-ld` on PATH; it is absent on this host |
| UI-02 | implemented-tested | `UiLifecycle`, `UiState`, `UiTasks`, `UiEvents`, `UiHarness`; `lifecycle_test` covers both pause/surface-loss orderings and proves focus/resume stay non-renderable until surface restoration; idle wait in `sdl3_wait_event_test`/`sdl3_lifecycle_stop_test` | none |
| UI-03 | implemented-tested (portable + real CPU-raster Skia) | `UiCore` commands, `UiRaster`, `UiPaint`, images/gradients/rounded/shadows, text pipeline, `UiTextMetrics` cache, geometry validation; pinned `check_skia.sh` fresh-process pixel digests and all showcase page/state PNGs; off-screen AppKit/Skia compositor; SDL device-loss fixture | the reproducible real-renderer gate passes with the compiler semantic-gate bypass; full semantic-enabled `ui_skia.elisa` compilation still stalls; color space is sRGB-only |
| UI-04 | implemented-tested (portable + iOS/Android backends) | `UiResponsive`, `UiMobileSurface`, `UiNavigation`, `UiServices`; shared counted UTF-8/UTF-16 codec gate; `check_uikit.sh`, `check_uikit_simulator.sh`, `check_uikit_touch.sh` | native permission/picker adapters; Android app/device IME gate not rerun in this refresh |
| UI-05 | implemented-tested (portable; hosted/device edges remain) | key/text/IME/focus/gesture/secure policy; `UiShortcuts`; word navigation; pinned Unicode corpus (1187 rows); `text_lifecycle_workflow_test` covers typed-handle editing, stale async validation, resource-triggered relayout, blur, teardown, and invalidation when identical programmatic replacement clears IME state; Android composition ranges now use the UTF-16 API directly | hosted Alt key-code is a WasmBrowser WIT gap (WB-05); physical-device IME/accessibility paths remain separate acceptance work |
| UI-06 | implemented-tested (portable + AppKit/UIKit) | `UiCore` semantics incl. Image/Group/List/Status/Alert; `accessibility_metadata_test`, `accessibility_geometry_test`; AppKit/UIKit adapters | hosted semantics has no WasmBrowser host channel (WB-05); real screen-reader device runs not verified here |
| UI-07 | implemented-tested (partial) | sizer/layout corpus, `UiConstraints`, `UiTheme`, `UiLocalization`, `UiValidation`, `UiIdentity`, `UiVirtualList` geometry + bounded realization/slot reuse; exhaustion reports a partial contiguous window without evicting another owner, covered by `virtual_list_test`; `UiTable` weighted growth continues past fixed/capped columns, covered by `ui_table_test`; `UiTree` flattening/navigation | third-party control groups |
| UI-08 | implemented-elisa-boundary | `UiResources` state machine and `UiResourcePresentation`; `resource_state_test` covers coalesced multi-owner leases, owner-scoped cancellation/disposal, aggregate visibility priority, and generation reuse; `resource_presentation_test` covers owner-preserving presentation/demand; SDL3 public showcase image workflow verifies real retained pixels | SDK/host transport integration |
| UI-09 | implemented-elisa-boundary | `UiFeatureView` coalesced owner leases, per-owner cancellation/disposal, token-safe deactivation tombstones, stale polling, and retry generations in `feature_view_test` | SDK/host component activation integration |
| UI-10 | implemented-tested (partial) | `UiInspector` hierarchy/bounds/dirty/focus/semantics/timings; `UiHarness`; release packaging; per-build toolchain display | SDK log/source-location integration |
| UI-11 | implemented-elisa-boundary | `UiRemote` negotiation/lifecycle/acknowledgement/limitations | WasmBrowser/SDK transport adapter |
| UI-12 | implemented-tested (C/C++/Rust) | `elisa_ui.h`, C host + C++17 header check, header↔symbol cross-check in `check_capi.sh`, bound ABI version, safe Rust wrapper + example (`check_rust.sh`) | Go bindings |
| UI-13 | implemented-tested (partial) | `UiBuild` version + compatibility; backend matrix; `check_performance.sh`; `test/stress_test.elisa` (sessions/churn/event pressure/command overflow/hostile geometry); `package_release.sh` with LICENSE/integrity and staged replacement that preserves an existing bundle on build failure; `docs/getting-started.md` tutorial; `docs/migrations.md` | reference-device budgets, GPU upload, idle-CPU, energy measurements |

The first implementation batch (plan §21) is partially evidenced: the public
backend/API map consumes pinned SDK bindings, and the hello reference screen
covers persistence, text, and resource errors on native backends. Current hosted
package verification is blocked until `wasm-component-ld` is available. Mobile
execution proceeds through the iOS/Android gates above.
