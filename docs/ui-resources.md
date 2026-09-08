# Resource presentation state

`UiResources` is the framework-owned half of on-demand resource loading. It
does not fetch bytes, verify packages, manage a cache, decode images, upload
fonts, or grant capabilities; those remain host/SDK responsibilities. It keeps
the state that a live view can safely present while that work happens elsewhere.

The public include is intentionally a small facade over cohesive Elisa modules:
`ui_resources_types.elisa` owns the fixed-capacity records and enums,
`ui_resources_identity.elisa` owns generation-safe identity and key matching,
`ui_resources_queries.elisa` owns read-only projections,
`ui_resources_demand.elisa` owns visibility hints and progress, and
`ui_resources_transitions.elisa` owns requests, completion, retry, and teardown.
Intrinsic dimensions remain an opt-in `ui_resource_metadata.elisa` extension.
Applications keep including `ui_resources.elisa`; the module layout is an
internal hygiene boundary, not a second public API.

```elisa
include "src/widgets/ui_resources.elisa"

UiResources::reset()
logo: UiResources::ResourceHandle = UiResources::request("images/logo", 7)
UiResources::set_progress(logo, network_fraction, decode_fraction)
UiResources::set_demand(logo, 10) # visibility/prefetch priority hint
if UiResources::state(logo) == UiResources::State.Ready:
    # Resolve the verified resource through the backend-owned renderer.
elif UiResources::state(logo) == UiResources::State.UnavailableOffline:
    # Keep the rest of the view interactive and offer retry/offline help.
```

Requests are idempotent by logical identifier while a record is live, so a
view rebuild cannot start duplicate work. Each handle contains a slot and a
generation. `dispose` advances the generation before releasing the identifier;
late completions holding the old token become no-ops even if the slot is reused.
`cancel` preserves the record for a possible re-request, while `retry` accepts
only recoverable denied/offline/failed states and returns a fresh generation
handle. Replace the old handle with that result; the old handle is invalidated
so late callbacks from the previous operation cannot update the retry.

Network and decode progress are separate normalized fractions. A value of 1.0
for network progress never implies that a resource is ready to paint. State or
progress changes raise `UiCore::Invalidation.Resources` and
`UiCore::Invalidation.Paint`; a host or diagnostic consumer can clear the
resource reason after it has consumed the change.

Visible views can add an idempotent `set_demand(handle, priority)` hint and
remove it with `clear_demand`. The priority is framework state for host/SDK
coalescing; it does not grant bandwidth, bypass cache policy, or force a fetch.
Hosts can inspect the bounded `demand_count()` / `demand_at(index)` snapshot or
select `highest_priority_demand()`. Each returned `DemandHint` includes the
generation-safe handle, owner, and priority; enumeration is deterministic and
does not expose resource-arena indexes or require a second native table.

Hosts may provide validated intrinsic geometry before decode/upload completes:

```elisa
UiResources::set_intrinsic_size(logo, 128.0, 72.0)
```

The dimensions are bounded, retained with the live logical generation, preserved
across `retry`, and cleared by `dispose`/`reset`. Presentation uses an intrinsic
dimension only when the corresponding `Options.reserved_width` or
`reserved_height` is exactly zero, so an explicit reservation always wins.
This keeps loading placeholders stable without giving a backend ownership of
layout metadata.

`snapshot()` returns bounded counts for the total live records and each
loading/ready/offline/denied/failed/cancelled state, plus the sticky overflow
flag. Diagnostic consumers can use that aggregate without inspecting resource
handles or keeping a native shadow table.

The fixed 128-record table and 256-byte logical identifier limit are deliberate
bounded behavior for native and Wasm tests. `overflowed` reports exhaustion;
invalid or oversized identifiers return `resource_invalid()` and do not create a record; use `resource_is_valid()` for stale-safe checks and `resource_key_matches()` for bounded diagnostics.

## Presentation policy

`src/widgets/ui_resource_presentation.elisa` keeps the user-facing mapping out
of every backend. `UiResourcePresentation::default_options` supplies reserved
geometry and placeholder/fallback colors for generic, image, font, and document
resources. `record(handle, options)` returns a read-only snapshot containing:

- the display state (`Placeholder`, `Loading`, `Ready`, `Offline`, `Denied`,
  `Failed`, or `Cancelled`);
- independent network/decode progress and whether a progress indicator is
  currently appropriate;
- placeholder/fallback visibility, retry availability, and interaction state;
- reserved size that can be used before intrinsic metadata or decoded bytes
  arrive.

`retry` and `cancel` are explicit actions that forward to `UiResources`; the
presentation layer never starts a fetch by itself. Failed resources carry a
typed `FailureKind`: `RetryableTransport` permits retry, while `Corrupt` and
`Incompatible` remain terminal until a new package/resource identity is
selected. This keeps offline/denied states recoverable without retry loops and
lets a host render the returned record with native, SDL, or hosted primitives.

`paint(box, record, options)` emits the backend-neutral placeholder, decoded
progress strip, or fallback card (including its diagnostic mark) through the
ordinary `UiCore` command list. It emits no command for `Ready`, leaving the
verified resource's image/font/document rendering to the host. Thus a backend
does not need a resource-state switch of its own.
