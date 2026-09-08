# Lifecycle-safe task tokens

`UiTasks` is the Elisa-owned lifetime half of asynchronous work. A host or SDK
starts the real operation with `start(owner)`, keeps the returned handle and
token, and calls `complete(handle, token, succeeded)` when it finishes. Elisa
accepts a completion only while the exact generation and current token are
pending; late, duplicate, or cancelled completions are rejected.

`cancel_owner(owner)` marks all pending work for a disposed/hidden view without
invalidating its diagnostic records. `dispose_owner(owner)` additionally advances
every generation and releases the records, so a callback from an old surface
cannot update a recycled slot. Individual `cancel` and `dispose` provide the
same distinction for one operation.

Task transitions invalidate paint and semantics, so loading, completion, and
error affordances update immediately without a backend-maintained shadow flag.

`UiLifecycle::reset()` and `UiLifecycle::stop()` are global teardown boundaries:
they call `UiTasks::reset()` so every outstanding handle becomes invalid before
the next surface/session can reuse view storage. `state(handle)` returns the
explicit `UiTasks::TaskState` enum; the descriptive name avoids collisions with
other framework modules when a backend combines multiple resource/state layers.

The fixed table is intentionally bounded and allocation-free. `snapshot()`
reports the total live records, pending, completed, failed, and cancelled counts
plus sticky capacity overflow. The module stores no native task pointer, callback, future, or result;
those remain host/SDK responsibilities behind the typed token boundary.
