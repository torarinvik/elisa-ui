# Lifecycle policy

`UiLifecycle` is the framework-owned interpretation of host lifecycle facts.
Native and hosted adapters still own their event loops and surfaces, but they
share the same typed phases:

- `New` → `Starting` → `Active`/`Inactive` during startup and focus changes;
- `Background` while a surface is suspended;
- `SurfaceLost` while the host must recreate presentation resources; and
- `Stopped` after close or teardown.

`begin()` advances a monotonic generation before a host creates objects. This
gives adapters and tests a stable session identity for rejecting callbacks from
an older run. `ready()` is called only after application initialization has
completed, so construction-time callbacks cannot enter the app frame pipeline.

The derived predicates are intentionally small and backend-neutral:

- `accepts_input()` is true only in `Active`;
- `can_render()` is true in `Active` and `Inactive`;
- `surface_available()` remains true for a backgrounded surface but is false
  for `SurfaceLost`; and
- `is_started()` covers all phases between `begin()` and `stop()`.

`stop()` is idempotent. `snapshot()` exposes the phase, generation, and those
predicates for inspectors and deterministic tests without exposing mutable
backend state. The headless `UiHarness`, SDL3, AppKit canvas, and WasmBrowser
adapters all use this policy; an adapter still performs the final native
operation (for example, stopping Cocoa's run loop) through its FFI boundary.
