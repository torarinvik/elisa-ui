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

An action is a bounded retained-widget target, not a boolean flag. The
`MAX_ACCESSIBILITY_NODES` one-past sentinel means “no action”; native adapters
must reject it before dispatch so a passive node cannot accidentally activate
widget slot zero. Dialogs use this sentinel and expose their actual controls as
separate child nodes.

The compatibility `UiCore::accessibility` builder remains unchanged for simple
controls. `accessibility_with_metadata` creates a fully described node, while
`accessibility_set_relationships` and `accessibility_set_range` let retained
widget emitters add facts after their existing role/value branch. All values
are normalized in Elisa before a backend can observe them.

`UiFlat::paint` derives links from the same retained tree used by layout and hit
testing. Non-semantic wrappers are skipped for parent lookup; visible semantic
siblings remain ordered by their retained tree links. Sliders and progress
indicators publish their normalized 0..1 range. A child crossing a scroll edge
remains navigable when any portion is visible, but its published bounds are
clipped to the intersection of all scroll ancestors, matching paint and
pointer hit testing. AppKit consumes the range
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

The Android Skia canvas serializes this same frame tree into a bounded snapshot
and copies it on the `android_main` owner thread. `ElisaAccessibilityView`
exposes the copied records as Android virtual nodes with platform roles,
bounds, labels/help, state, range and collection metadata. Click, focus, slider,
and virtualized-list scrolling actions return through a bounded queue and are
resolved against the current semantic frame before touching retained widgets.
Password-field text and caret/selection offsets are omitted from the Android
snapshot; text editing remains owned by the framework's focused field and
Android `InputConnection`. The Android package
gate checks the built adapter and, when a device is attached, reads the actual
hierarchy through `uiautomator`; physical-device TalkBack and keyboard
acceptance remain separate plan work.

Applications can opt a retained widget into semantic and inspector redaction
with `UiHandles::set_accessibility_sensitive`. Its label becomes the generic
“Sensitive content” label; help, text values, selection, ranges, and collection
metadata are omitted, and an already-published core node is scrubbed
immediately. Virtual-row providers can mark an `UiVirtualAccessibility::Item`
as `sensitive`, causing the same content/state removal before the borrowed row
leaves `UiFlat`; marking the list itself sensitive applies to all provider
rows, and sensitive rows use their logical position instead of the app's stable
identifier for native accessibility identity. The Android native-controls
adapter also maps the marker to a generic `AccessibilityNodeInfo`, suppresses
text-bearing events, removes exposed ranges/selection and copy/cut actions, and
keeps the control's visible/editing behavior unchanged. The Android package
gate checks the compiled JNI descriptor and delegate bytecode; TalkBack
acceptance remains open.

The UIKit native-controls adapter maps the marker to a generic accessibility
label and empty value, suppresses placeholder/help, and denies text-field
Copy/Cut while preserving the visible field value. AppKit now does the same
accessibility-value redaction for native labels, text fields, buttons, sliders,
and progress indicators; text-field placeholder/help and native help are
suppressed, while visible text and control state remain intact. Sensitive text
fields receive a privacy-aware native field editor that disables Copy/Cut and
rejects direct copy/cut and selection writes to pasteboards; clearing
sensitivity restores native menu validation. Its headless Cocoa fixture covers
these behaviors, but is not a live VoiceOver/Accessibility Inspector acceptance
run. GTK now replaces native accessible labels, suppresses help/placeholders,
and masks range values and checked state while preserving their visible/model
state. On GTK 4.14+, a `GtkEntry` subclass implements `GtkAccessibleText` and
returns empty text, caret, selection, and geometry while marked sensitive;
ordinary text and native editing remain intact. Its macOS and Linux/Xvfb
fixtures exercise the accessible-text interface directly, but live Orca
exposure remains open. Win32 now applies HWND UIA/MSAA
annotations for a generic name, suppressed help/value/range/toggle state, and
marks sensitive edits as password fields with TextPattern unavailable; a
window subclass also blocks `WM_COPY`/`WM_CUT`, and placeholders/tooltips are
suppressed. Clearing the marker removes the annotations. The Win32 PE cross-link
passes, but these properties have not been exercised on Windows or inspected
with Narrator/UIA, so native exposure remains unverified. Screenshot/export-
trace redaction is separate work.
