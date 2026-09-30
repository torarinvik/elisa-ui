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
or tilt. UIKit and Android currently normalize touch to the primary pointer;
UIKit forwards one touch from each native set. Stylus and multi-contact
identity therefore cannot be recovered from this event stream.

The separate `UiGestures` state machine accepts identified contacts and
timestamps and recognizes tap, long-press, drag, and two-contact pinch, but no
production adapter currently feeds it or maps its snapshots to widget actions.
Its contact cancellation is also separate from pointer capture. Until that
bridge exists, the gesture policy is tested as a backend-neutral component,
not as native touch/stylus support.

For the existing single-pointer widget path, `PointerEvent.Leave` clears hover
but intentionally retains a pressed control or scrollbar capture until the
matching release. `UiFlat::handle()` routes `FocusLost` through
`UiFlat::lifecycle()` to `cancel_interaction()`, which releases active
presses/scroll capture and clears transient modifier state.
`UiGestures::cancel_all()` is the corresponding contact-table operation, but
is not yet wired to that lifecycle path.
