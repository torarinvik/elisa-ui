# Deterministic test harness

`UiHarness` is the platform-free driver for interaction and frame tests. It
lives in [`src/test/ui_harness.elisa`](../src/test/ui_harness.elisa) and keeps
test policy in Elisa instead of opening SDL/AppKit/WasmBrowser surfaces.

```elisa
include "src/test/ui_harness.elisa"

UiHarness::start(640.0, 480.0)
UiHarness::dispatch(UiCore::PointerEvent.Down(
    at: UiCore::Vec2(24.0, 18.0),
    button: UiCore::PointerButton.Primary.i32()))
UiHarness::set_time(0.50)
UiHarness::frame()
```

The harness calls the normal `app_init`, `app_event`, and `app_frame` contract.
An application that uses `UiFlat` routes the injected event to
`UiFlat::handle` in `app_event`, exactly as its production entrypoint does.
`frame()` clears the command and semantic batches with `UiCore::begin_frame`
before invoking `app_frame`, so tests can inspect command counts, overflow flags,
semantic counts, invalidation reasons, and `UiCore::frame_delay()` without a
painter. `UiCore::Invalidation.Layout` and `Resources` are durable until the
owner clears them; `Paint`, `Semantics`, and `Animation` are frame-local and are
cleared at the next `begin_frame`.

`UiHarness` also injects logical resource requests, progress and state changes
through `request_resource`, `set_resource_progress`, `set_resource_demand`, and
`set_resource_state`,
with owner-scoped `cancel_resources_for_owner` and
`dispose_resources_for_owner` helpers for view teardown.
`stop()` resets resource generations before making late callbacks no-ops, so an
async completion cannot update a disposed slot.

`set_time` accepts monotonic absolute seconds; `advance_time` adds a positive
delta and ignores negative, NaN, or infinite input. The clock never moves
backwards. `resize`, `focus_lost`, and `focus_gained` are convenience helpers
for the corresponding lifecycle events. `stop()` makes late callbacks and
frames no-ops, which lets tests exercise disposal boundaries.

The production backends remain responsible for their native event loops and
clocks. This module is intentionally a deterministic injection seam, not a
second backend.
