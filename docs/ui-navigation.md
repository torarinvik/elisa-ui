# Back navigation policy

`UiNavigation` keeps desktop Escape, mobile back gestures/buttons, and hosted
navigation requests on one Elisa-owned policy. A bounded entry records an
application owner, whether the view is dirty, and one of three policies:

- `Allow` returns `Navigate`.
- `Consume` returns `Consumed` for an interaction handled inside the view.
- `Confirm` returns `Confirm` only while the entry is dirty.

`request_back()` reports a decision but never silently removes a view. An
application can save or otherwise accept the transition and call `commit(handle)`;
for a dirty `Confirm` entry it calls `resolve_confirmation(true)` after the
confirmation UI succeeds, or `resolve_confirmation(false)` to leave the view
and its edits intact. This keeps OS navigation available instead of trapping it
inside a native shim.

The stack is strict: only the current top entry can be committed. If a newer
entry appears while a confirmation is pending, accepting the older prompt is
consumed without removing the newer view; the application can request back
again for the new top entry.

Entries and confirmation state use generation-checked handles. `dismiss_owner`
releases every entry belonging to a disposed view/task and invalidates its
handles, so a late callback cannot pop a recycled surface. Capacity exhaustion
is sticky and observable through `snapshot()`/`overflowed()`.

The module contains no platform objects or callbacks. Native and hosted
adapters only translate their raw back fact, apply the returned decision, and
perform the host-specific navigation or presentation step.
