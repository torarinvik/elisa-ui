# Gesture policy

`UiGestures` is a bounded, backend-neutral contact state machine. Native and
hosted adapters provide a contact identity, phase, position, and monotonic
timestamp; Elisa owns capture, thresholds, classification, cancellation, and
the resulting gesture snapshot.

The fixed eight-contact table recognizes taps (up to 350 ms), long presses
(600 ms or longer without movement), drags (8 logical pixels of movement), and
two-contact pinch scale. Duplicate identities and capacity exhaustion fail
closed and remain observable. `cancel_all()` is the lifecycle hook for focus or
surface interruption, so no late move/up callback can target a dead capture.
`UiMobileSurface` invokes it on accepted focus loss, background, surface loss,
and stop transitions; new mobile sessions reset the table.
Touch ID `0` is valid; `NO_CONTACT_ID` is the distinct snapshot marker used
when no secondary contact is active.

UIKit and Android now translate native callbacks into portable identified
contact facts, preserving source and monotonic time. UIKit forwards every
UITouch; Android forwards all moved/cancelled pointers and the changed pointer
on down/up. A bounded identity map avoids native-pointer truncation. Gesture
snapshots update before application contact callbacks. UIKit cancels its
compatibility pointer when a second contact arrives, without resuming that
press when one finger lifts. Retained routing is described below; physical
stylus/multitouch acceptance remains open.

## Retained gesture targets

`UiHandles::set_gesture_target(handle, true)` opts a live control, canvas, or
ancestor container into gesture callbacks. Registration is bounded to 32
targets and capture to eight contacts. The nearest registered ancestor of the
initial interactive hit owns that contact until release/cancellation, even when
it moves outside the initial bounds. If there is no interactive hit (for
example, a blank part of a canvas), routing checks visible registered targets
in reverse paint order and captures the topmost containing surface. Hidden,
disabled, deregistered and old-tree targets are rejected.
Registration and the callback snapshot are retired when the tree epoch changes.
Deregistering a target immediately retires its contact captures; registering
the same target again cannot make an old release into a new gesture callback.

Opted-in targets receive `WidgetEvent.GestureDrag`, `GesturePinch`,
`GestureLongPress` or `GestureCancelled` through the existing widget callback.
`UiHandles::gesture_snapshot()` exposes the classified position/delta/scale/time
for that callback. Pinch requires both contacts to be captured by the same
target; application code applies the scale to its model rather than the
framework inventing a zoom transform. Hello demonstrates app-owned pinch zoom
over a passive canvas; its rendered artwork radius follows the bounded zoom
model in `hello_zoom_workflow_test`. Classified gestures cancel compatibility
pointer capture before notification, so a long press does not also click.
Tap activation remains on the existing pointer path. Unregistered legacy
widgets never receive the new ordinals. Native delivery's exact recognition
handoff is consumed once; direct typed/C/harness contact routing recognizes
the fact itself. Focus loss retires recognizer and retained gesture captures.
Each lifecycle cancellation callback carries its own captured identity,
last bounded position and elapsed duration, not the recognizer's final global
contact snapshot. The two-target UIKit host regression verifies that each
cancelled contact identity belongs to its callback target.

`uikit_surface_test` covers real native callback routing into opted-in pinch,
long press, cancelled contacts, drag outside bounds, hidden-target rejection,
legacy callback isolation and direct typed-contact long-press recognition.
The fixture also covers deregister/re-register retirement. Native contact
timestamps use a stream-relative origin subtracted before float narrowing;
the production clock host test preserves tap/long-press precision at very
large system uptimes and rejects backward/nonfinite native timestamps.
These are host checks below the shim, not physical stylus acceptance or a
native device pinch test. When a contact has no explicit gesture target, the
retained router can capture the nearest scroll viewport instead. A drag begins
scrolling at the shared 8-point threshold, includes pre-threshold movement,
and bubbles same-axis deltas through nested viewports when an inner viewport
reaches an edge. A short, bounded release-velocity sample drives decaying
scroll motion from the retained frame clock; the shared reduced-motion
preference disables that momentum without changing direct finger tracking.
Focus loss, a new contact, tree replacement, and a cancelled contact retire
the motion. `touch_scroll_test` covers thresholding, continuous drag deltas,
inertia, nested edge handoff, reduced motion, and focus-loss cancellation.
Physical-device scroll feel, stylus acceptance, and physical-device zoom
acceptance remain open.

Additional host checks: `contact_event_test`, `mobile_contacts_test`, and
`uikit_surface_test` pass for wire validation, bounded identity mapping,
source preservation, pinch snapshot visibility and capture cancellation.
UIKit Hello simulator and Android Showcase ARM64 build with the new ingress.
These use the stale compiler below. The simulator HID gate has been rerun with
the new ingress; its cancellation assertion now requires the shared recognizer
to report Cancelled with zero active contacts, in addition to released retained
capture. Both cancellation/tap and committed-text XCUITests pass.
`android_dispatch_test` verifies queued reentrancy, gesture snapshot visibility,
and rejection of queued contacts across a replacement session.
`check_android_contacts.sh`, included in the ordinary suite, compiles the
production MotionEvent transport against host facts and verifies changed-slot
down/up, reordered pointer IDs, all-pointer move/cancel, logical coordinates,
native source/time, and invalid slot/identity rejection. `check_android.sh`
passes package/export checks including `elisa_android_contact`; its device
half is skipped because no Android device is attached.
