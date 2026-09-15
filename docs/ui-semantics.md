# Portable semantic nodes

`UiCore::AccessibilityNode` is the backend-neutral semantic record emitted
alongside each retained frame's drawing commands. Its portable role set
includes `Dialog` for modal containers, `Image`, `Group` for custom controls,
`List` for virtualized lists, and `Status`/`Alert` for live status changes and
errors. `UiDialog` can
project its copied title/message and typed result into this role directly;
AppKit maps it to its stable group-container role while hosted adapters keep the
same role value.

Live text roles matter because a message that changes without a notification is
invisible to a screen reader. `Status` and `Alert` use the text value kind in
both native adapters, so a changed `text_value`/`revision` posts an AppKit value
notification and is spoken by VoiceOver. UIKit marks `Status` as updating
frequently and `Alert` as static text, and neither is presented as an
activatable element. AppKit maps `Image`/`Group`/`List` to Cocoa's image,
group, and list roles; the role strings are imported framework constants, so no
new shim state is introduced.

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

The AppKit canvas now publishes ordinary semantic groups as a checked batch:
Elisa validates bounded parent chains and ordered sibling links, creates the
child arrays, and sends only semantic roots plus those arrays through the
existing graph transaction. The native shim validates same-window identities
before assigning `accessibilityChildren`/`accessibilityParent`, so a malformed
hierarchy leaves the previous native graph intact. Collection-positioned nodes
remain owned by the virtual-list row projection and are not duplicated in the
ordinary hierarchy.

The semantic buffer remains fixed-capacity and deduplicated by stable ID. A
duplicate declaration replaces the prior node in its original position, and
overflow is reported rather than growing an unbounded frame allocation.
The bounded Elisa-owned ID-to-slot index makes duplicate declarations and
relationship patches constant-time while retaining a stale-slot validation
guard at the public lookup boundary.

`UiCore::accessibility_diff` compares two nodes and returns typed change bits
for identity, structure, geometry, state, value, text, selection, and range.
Adapters can use the mask to issue incremental native notifications while the
retained frame remains the sole semantic source of truth. UIKit publishes only
the committed roots from its view container; `ui_uikit_accessibility_hierarchy`
resolves ordinary child/count/index queries from that same relationship
history, so nested groups are traversable without a native widget graph.
