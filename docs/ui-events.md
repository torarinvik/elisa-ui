# Bounded event ingress

`UiEvents` is the shared Elisa-side ingress queue for translated native,
hosted, C, and deterministic-harness events. Adapters first create a typed
`UiCore::Event`, then enqueue it; the queue owns FIFO ordering and a fixed
capacity of 256 records.

When the queue is full, the incoming event is rejected rather than replacing a
previous event. `overflowed`, `dropped`, and `pending` remain available through
`UiEvents::Snapshot` and `UiInspector::Frame`, so an embedding can surface or
apply backpressure instead of treating loss as success. Overflow is sticky for
the current backend session and clears on the next adapter reset.

Synchronous callbacks drain immediately, preserving the existing application
ordering. SDL drains a poll burst after native event decoding; all paths use
the same queue and therefore share the same loss behavior without putting a
second event model in C or Objective-C.
