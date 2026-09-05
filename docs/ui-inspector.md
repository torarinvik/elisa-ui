# Retained-tree inspector

`src/widgets/ui_inspector.elisa` is a deterministic, headless diagnostic view
of the same `UiFlat` state used for layout, painting, input, and semantics. It
does not maintain a shadow tree or call a native debugger API.

```elisa
include "src/widgets/ui_inspector.elisa"

snapshot: UiInspector::Frame = UiInspector::frame()
node: UiInspector::Node? = UiInspector::inspect(save)
```

`Frame` reports the viewport, shared lifecycle phase/generation and its input
and rendering predicates, deferred layout state, frame clock/deadline,
command/semantic buffer counts and overflow flags, and the five typed
invalidation reasons (`Layout`, `Paint`, `Semantics`, `Resources`, and
`Animation`). `Node` reports a typed
lifetime handle, parent/child/sibling relationships, resolved bounds,
min/max/grow/margin constraints, visibility/enabled/focus/selection state,
value, text, help, and its matching semantic node. Tree navigation remains
typed, so a stale handle produces no record and cannot inspect a recycled slot.

Secure text is redacted as `[secure]` in diagnostic nodes and semantic copies;
selected text is cleared. This keeps inspector output safe for logs, snapshots,
and future source-linked tooling. The module is allocation-free and can be
used by a native debugger, a hosted diagnostics panel, or a headless test.
