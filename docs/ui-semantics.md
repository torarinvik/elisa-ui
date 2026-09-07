# Portable semantic nodes

`UiCore::AccessibilityNode` is the backend-neutral semantic record emitted
alongside each retained frame's drawing commands. Its portable role set
includes `Dialog` for modal containers. `UiDialog` can
project its copied title/message and typed result into this role directly;
AppKit maps it to its stable group-container role while hosted adapters keep the
same role value.

Existing role, label, help, bounds, action, enabled/focused/selected state, text
values, and revision fields are supplemented by:

- optional `parent_id`, `first_child_id`, and `next_sibling_id` links using
  `UiCore::MAX_ACCESSIBILITY_NODES` as a bounded sentinel; and
- optional numeric ranges (`has_range`, `range_min`, `range_max`) with an
  explicit `range_conflict` bit when malformed bounds were repaired.

The compatibility `UiCore::accessibility` builder remains unchanged for simple
controls. `accessibility_with_metadata` creates a fully described node, while
`accessibility_set_relationships` and `accessibility_set_range` let retained
widget emitters add facts after their existing role/value branch. All values
are normalized in Elisa before a backend can observe them.

`UiFlat::paint` derives links from the same retained tree used by layout and hit
testing. Non-semantic wrappers are skipped for parent lookup; visible semantic
siblings remain ordered by their retained tree links. Sliders and progress
indicators publish their normalized 0..1 range. AppKit consumes the range
metadata when assigning native accessibility values and treats relationship or
range changes as semantic-layout changes; Cocoa object/protocol plumbing stays
in the native shim.

The semantic buffer remains fixed-capacity and deduplicated by stable ID. A
duplicate declaration replaces the prior node in its original position, and
overflow is reported rather than growing an unbounded frame allocation.
The bounded Elisa-owned ID-to-slot index makes duplicate declarations and
relationship patches constant-time while retaining a stale-slot validation
guard at the public lookup boundary.

`UiCore::accessibility_diff` compares two nodes and returns typed change bits
for identity, structure, geometry, state, value, text, selection, and range.
Adapters can use the mask to issue incremental native notifications while the
retained frame remains the sole semantic source of truth.
