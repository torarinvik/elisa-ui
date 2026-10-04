# Retained-tree inspector

`src/widgets/ui_inspector.elisa` is a deterministic, headless diagnostic view
of the same `UiFlat` state used for layout, painting, input, and semantics. It
does not maintain a shadow tree or call a native debugger API.

```elisa
include "src/widgets/ui_inspector.elisa"

snapshot: UiInspector::Frame = UiInspector::frame()
node: UiInspector::Node? = UiInspector::inspect(save)
first: UiInspector::Node? = UiInspector::node_at(0)
```

Use `frame_with_system_contrast(true)` when the host reports high contrast so
resolved geometry metrics reflect the active platform preference.

`Frame` reports the viewport, shared lifecycle phase/generation and its input
and rendering predicates, deferred layout state, frame clock/deadline,
stage timing metrics (application, semantics, and paint), independent
layout/text/resource work timings, command/semantic buffer counts and overflow
flags, and the five typed
invalidation reasons (`Layout`, `Paint`, `Semantics`, `Resources`, and
`Animation`). `Node` reports a typed
lifetime handle, parent/child/sibling relationships, resolved bounds,
min/preferred/max/grow/margin constraints, visibility/enabled/focus/selection state,
value, text, help, and its matching semantic node. Tree navigation remains
typed, so a stale handle produces no record and cannot inspect a recycled slot.
`node_at` offers a bounded ordinal snapshot for tooling enumeration; it returns
the same typed record and never exposes the retained arena index as a handle.

`Node.constraints` includes per-axis declared and effective preferred sizes,
`width_conflict`/`height_conflict` facts, and low/high clamp flags. A conflict
means a declared range was contradictory or the allocated frame fell outside
the normalized range. A maximum below the required minimum remains visible as
declared, is reported as a conflict, and is ignored for allocation. If a parent
is too small, the default `Compress` policy may place a child below its minimum
and the inspector reports that low clamp. Panels can opt into `Clip` or
`Visible` overflow behavior to shrink preferences only down to minimums; `Clip`
also clips descendants to the padded content box, while `Visible` leaves their
overflow available to paint, hit testing and visible semantic bounds. Scroll
viewports retain their independent viewport clipping. Zero preferred dimensions
mean automatic sizing: measured intrinsic minimums for leaves and child-derived
preferences for ordinary containers.

`Frame.localization` is the same bounded `UiLocalization::Snapshot` used by
the application: it includes the canonical active tag, direction, monotonic
revision, and truncation flag. This lets diagnostics detect a locale-driven
rebuild without keeping a second native or tooling-side locale table.

`Frame.theme` likewise exposes the normalized `UiTheme::Snapshot`, including
the active preferences and monotonic revision, so runtime appearance changes
are visible to diagnostics without a backend shadow state.
`Frame.theme_metrics` reports the resolved geometry tokens used by the flat
renderer, including effective touch-target and focus-ring sizes.

`Frame.work` contains host-clock-driven scopes for layout, text, and resource
work. Each kind can be measured independently (including nested kinds), while
duplicate begins and unmatched finishes fail closed. Scope durations are
allocation-free, reset at each frame, and retain an overflow flag rather than
emitting a non-finite diagnostic value.

`Frame.text_metrics` reports the active font/scale generations and bounded
line-height/width query and miss counters from `UiTextMetrics`, making cache
invalidations and metric pressure visible in the same diagnostic snapshot.

`Frame.resources` reports aggregate requested, ready, offline, denied, failed,
and cancelled resource counts plus overflow state. It keeps resource diagnostics
available without exposing the resource arena or borrowed renderer handles.

`Frame.remote` exposes the backend-neutral remote session snapshot, including
negotiated presentation, scale, lifecycle generation, input acknowledgement,
and disconnect-overlay facts. It remains a value copy and does not expose
transport objects.

Secure text is redacted as `[secure]` in diagnostic nodes and semantic copies;
selected text is cleared. This keeps inspector output safe for logs, snapshots,
and future source-linked tooling. The module is allocation-free and can be
used by a native debugger, a hosted diagnostics panel, or a headless test.

For retained-command diagnostic images or traces, use
`UiPaint::replay_diagnostic` or the `UiCore::diagnostic_command_*` accessors.
During `UiFlat::paint`, secure widgets and widgets marked with
`set_accessibility_sensitive` collapse to one opaque fill covering their
bounds. This removes their text, value-dependent paint, images, selection, and
caret from the diagnostic stream while leaving the ordinary command stream
unchanged for rendering. Diagnostic exporters must not serialize
`UiCore::command_at` directly. Native-control screenshots and platform-owned
trace exporters still need to adopt the same policy at their own capture
boundary. The opt-in is widget-local, matching inspector and semantic
redaction; child widgets opt in independently. A sensitive scroll widget's
late-painted scrollbar channel receives its own narrow mask.
