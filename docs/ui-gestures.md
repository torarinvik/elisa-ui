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
Touch ID `0` is valid; `NO_CONTACT_ID` is the distinct snapshot marker used
when no secondary contact is active.

The module deliberately does not claim native touch-device coverage yet. A
backend must still translate its OS contact callbacks into these facts and map
the snapshot to widget actions; it no longer needs to duplicate gesture policy.
