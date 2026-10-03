# Bounded event ingress

`UiEvents` is the shared Elisa-side ingress queue for translated native,
hosted, C, and deterministic-harness events. Adapters first create a typed
`UiCore::Event`, then enqueue it; the queue owns FIFO ordering and a fixed
capacity of 256 records.

When the queue is full, ordinary pointer, key, scroll, and gamepad input is
rejected rather than replacing a previous event. Authoritative lifecycle facts
(quit, resize, and focus transitions) may replace the oldest queued physical
input so teardown and focus recovery cannot be stranded behind stale traffic.
`overflowed`, `dropped`, and `pending` remain available through
`UiEvents::Snapshot` and `UiInspector::Frame`, so an embedding can surface or
apply backpressure instead of treating loss as success. Overflow is sticky for
the current backend session and clears on the next adapter reset.

Synchronous `UiCore::Event` callbacks drain immediately, preserving the
existing application ordering. SDL drains a poll burst after native event
decoding; all paths use the same queue and therefore share the same loss
behavior without putting a second event model in C or Objective-C.

## Event vocabulary and delivery

`UiCore::Event` is the portable queued vocabulary for lifecycle changes
(`Quit`, `Resize`, `FocusGained`, `FocusLost`), physical keys (`KeyEvent.Down`
and `Up`), pointer transitions and scroll (`PointerEvent`), and gamepad input.
`PointerEvent.Cancel` releases pointer capture without activation. Its wire
ordinal is 14; the existing 24-byte record and earlier ordinals are unchanged.
Cancellation is an authoritative control signal: it survives input gating and
can replace queued physical input when the queue is full.
`ContactEvent.Update` adds identified contact phases at wire ordinals 15–18
(began, moved, ended, cancelled). The record remains 24 bytes: `code` carries
the unsigned identity bits, `x/y` logical position, `dx` monotonic seconds,
and `dy` the integer tool tag (finger 0, stylus 1, indirect 2, unknown 3).
Invalid phases, tools, nonfinite coordinates/time and negative time are rejected.
UIKit and Android map native identities without truncation, then update the
shared recognizer at queued application delivery. Android's reentrant callbacks
now use the same bounded FIFO; generation checks discard old-session traffic.
`InputEvent` is the common supertype for physical input; lifecycle events are
not input. Key identities and pointer-button values are normalized into
`UiCore` enums at the adapter boundary.

Committed text and live IME composition deliberately do not travel as
`UiCore::Event` records. The application callbacks `app_text_input(UTF-8)` and
`app_text_editing(UTF-8, selection-start, selection-length)` carry those text
payloads on a separate path. SDL and the C bridge express composition
selection offsets as Unicode-scalar counts; AppKit and UIKit native text
protocols use UTF-16 offsets, translated by their adapters. The retained
editor stores ranges as UTF-8 byte offsets and normalizes selection to
grapheme boundaries; see [text-input policy](ui-text-input.md) for the full
unit contract.

This split has an important limit: the callbacks describe composition
updates and committed text, but there is no portable tagged event for
composition begin, commit, or cancel. SDL's empty editing payload clears its
marked run; native `unmarkText` ends marking while retaining the text. Those
are distinct native operations, not a shared cancellation event. Adapters
that interleave text with queued key events must preserve their native order;
SDL explicitly drains earlier queued events before forwarding borrowed text.

## Pointer capture, contacts, and lifecycle

`PointerEvent` is a single anonymous pointer. Its `Move`, `Down`, `Up`,
`Leave`, and `Scroll` variants carry no source kind, contact identity, pressure,
or tilt. UIKit and Android retain this compatibility path, but also deliver
identified `ContactEvent.Update` facts with source and time. UIKit forwards all
contacts in each native set; Android uses stable pointer IDs rather than slots.
Identity/source are available through contact events, not anonymous pointers.

The separate `UiGestures` state machine accepts identified contacts and
timestamps and recognizes tap, long-press, drag, and two-contact pinch. Native
contact delivery feeds it before application callbacks, and opted-in retained
targets route its snapshots into gesture widget callbacks. `UiMobileSurface` clears the
gesture table on accepted focus loss, backgrounding, surface loss, and stop,
and resets it for a new session. Pressure/tilt and physical-device stylus
acceptance remain unimplemented/unverified respectively.

Native timestamp adapters subtract a shared contact-stream origin in double
precision before narrowing to the portable float record. Time is monotonic
within a stream and restarts for a new stream; absolute system uptime is not
part of the contact contract. The shared C clock rejects backward/nonfinite
native times. `check_android_contacts.sh` covers 100-million-second uptime
without losing the 340 ms tap or 610 ms long-press timing distinction.

For the existing single-pointer widget path, `PointerEvent.Leave` clears hover
but intentionally retains a pressed control or scrollbar capture until the
matching release. `UiFlat::handle()` routes `FocusLost` through
`UiFlat::lifecycle()` to `cancel_interaction()`, which releases active
presses/scroll capture and clears transient modifier state.
UIKit and Android native touch cancellation now produce `PointerEvent.Cancel`,
which releases button, slider, text-selection, and scrollbar capture while
preserving keyboard capture and modifiers. Their lifecycle callbacks also
deliver it after input becomes inactive. `UiGestures::cancel_all()` is wired
to the mobile lifecycle transitions above.

Focused evidence (2026-10-03): `event_wire_test`, `event_queue_test`,
`widget_layout_geometry_test`, `mobile_surface_test`, `uikit_input_test`, and
`uikit_surface_test` pass, covering a late release after cancellation, keyboard
capture preservation, a full ingress queue, real UIKit callback routing below
the shim, and contact cancellation at each mobile interruption. These runs
explicitly use stale Stage1 product `5c926548…8428e324c` while a separate
compiler seed is running; they do not establish fresh-compiler acceptance.
The UIKit Hello simulator app and Android Showcase ARM64 APK build, and the
C, Go, and Rust embedding gates pass on the same product.
`check_uikit_touch.sh` also passes two XCUITests on the dedicated iOS 26.5
simulator: a system HID drag triggers UIKit cancellation, the app publishes
confirmation that retained capture is released, two following taps activate
exactly once each, and committed software-keyboard text reaches semantics.
The host UIKit fixture additionally verifies that a cancellation callback can
start a replacement session without the old stop request retiring it.
