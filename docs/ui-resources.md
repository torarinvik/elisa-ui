# Resource presentation state

`UiResources` is the framework-owned half of on-demand resource loading. It
does not fetch bytes, verify packages, manage a cache, decode images, upload
fonts, or grant capabilities; those remain host/SDK responsibilities. It keeps
the state that a live view can safely present while that work happens elsewhere.

The public include is intentionally a small facade over cohesive Elisa modules:
`ui_resources_types.elisa` owns the fixed-capacity records and enums,
`ui_resources_identity.elisa` owns generation-safe identity and key matching,
`ui_resources_owners.elisa` owns independent observer leases,
`ui_resources_queries.elisa` owns read-only projections,
`ui_resources_demand.elisa` owns visibility hints and progress, and
`ui_resources_transitions.elisa` owns requests, completion, retry, and teardown.
Intrinsic dimensions remain an opt-in `ui_resource_metadata.elisa` extension.
`ui_resource_operations.elisa` associates generations with host-owned async
operation identifiers and preserves cancellation acknowledgements.
Applications keep including `ui_resources.elisa`; the module layout is an
internal hygiene boundary, not a second public API.

```elisa
include "src/widgets/ui_resources.elisa"

UiResources::reset()
logo: UiResources::ResourceHandle = UiResources::request("images/logo", 7)
UiResources::set_progress(logo, network_fraction, decode_fraction)
UiResources::set_upload_progress(logo, upload_fraction)
UiResources::set_demand_for_owner(logo, 7, 10) # visibility/prefetch hint
if UiResources::state(logo) == UiResources::State.Ready:
    # Resolve the verified resource through the backend-owned renderer.
elif UiResources::state(logo) == UiResources::State.UnavailableOffline:
    # Keep the rest of the view interactive and offer retry/offline help.
```

Requests coalesce by logical identifier while a record is live, so several
views share one handle and do not start duplicate host work. Each `(resource,
owner)` pair has its own bounded lease; repeating a request for that owner is
idempotent, and a different owner does not replace the existing observer.
Owner identities are nonzero; `0` is reserved for an invalid/no-owner result
and is rejected by `request`.
`owner_count()` and `owns()` inspect membership; `owner()` is a compatibility
projection of the first live owner. Each handle contains a slot and a
generation. `dispose(handle)` is the forceful, global release: it advances the
generation before releasing the identifier, so late completions holding the
old token become no-ops even if the slot is reused. For ordinary view teardown,
`dispose_owner(owner)` removes only that owner's leases and frees a resource
only after its final owner leaves. If that generation still has a bound host
operation, disposal marks its operation record `cancellation_requested` before
invalidating the resource. Explicit cancellation and last-owner cancellation
do the same; removing one of several owners leaves shared work running. The
host can enumerate `operation_at(index)`, send the cancellation, then call
`forget_operation(id)` after acknowledgement; the stale resource generation
cannot accept a late result in the meantime.

`cancel(handle)` explicitly cancels the shared operation. Use
`cancel_for_owner(handle, owner)` or `cancel_owner(owner)` when one view should
stop observing it; the host request is marked Cancelled only after the final
owner leaves. A cancelled record remains available for a later request, which
starts a fresh generation. `retry` accepts only recoverable denied/offline/
failed states and returns a fresh generation handle. Replace the old handle
with that result; late callbacks from the previous operation cannot update the
retry.
`reset()` also requests cancellation for every bound host operation before it
invalidates resource generations. Operation records remain enumerable and must
be forgotten after host acknowledgement, including when reset happens during
application stop or restart.
`Ready` is stable for its generation: a late offline, denied, or failure result
cannot discard usable content. Explicit cancellation remains available; a new
host operation must retry a recoverable failure or release/cancel the old
generation before requesting again.

Network, decode, and renderer-upload progress are separate normalized
fractions. A value of 1.0 for any progress channel never implies that a
resource is ready to paint; the operation owner publishes `Ready` only after
all required work succeeds. Async host operations do so through
`complete_operation`; SDL3's RGBA32 image binder reports upload completion and
completes the matching host operation only after `SDL_UpdateTexture` succeeds.
Skia's `complete_uploaded_image` publishes a decoded/uploaded generation after
its renderer binding succeeds, then settles the matching host operation (or
uses the same progress/state path when no operation is bound).

AppKit's `UiAppKitCanvasResources::complete_uploaded_image` and UIKit's
`UiUIKitResources::complete_uploaded_image` apply that contract to their
generation-keyed CGImage binding tables: each requires completed network and
decode stages, binds the host-owned image, and publishes `Ready` only after
the renderer binding/upload stage succeeds. The host must call
`forget_uploaded_image` when that resource generation is released; the adapter
removes only the matching slot/generation binding and does not take ownership
of the CGImage. `appkit_canvas_image_upload_test` and
`uikit_image_upload_test` validate staged state and binding lifecycle, not
native pixel rendering. Production host decode callbacks and device-level
image presentation remain unverified.

Hosts can report upload through `poll_upload_operation(handle, operation_id,
fraction)`, which rejects stale or foreign operation IDs just like
transport/decode polling. State or progress changes raise
`UiCore::Invalidation.Resources` and
`UiCore::Invalidation.Paint`; a host or diagnostic consumer can clear the
resource reason after it has consumed the change.
Progress is monotonic within one resource generation; out-of-order decreases
are rejected, while `retry` starts a fresh operation with all progress reset.

Visible views can add an idempotent `set_demand_for_owner(handle, owner,
priority)` hint and remove it with `clear_demand_for_owner`. The compatibility
helpers `set_demand` and `clear_demand` target the first live owner. Each
owner's priority is retained independently; the host sees one aggregate hint
at the highest live priority, with a deterministic owner on ties. Demand is
framework state for host/SDK coalescing; it does not grant bandwidth, bypass
cache policy, or force a fetch.
Hosts can inspect the bounded `demand_count()` / `demand_at(index)` snapshot or
select `highest_priority_demand()`. Each returned `DemandHint` includes the
generation-safe handle, owner, and priority; enumeration is deterministic and
does not expose resource-arena indexes or require a second native table.
When a view becomes hidden, `clear_demand_owner(owner)` releases all of that
owner's hints without cancelling its logical records; disposal can still use
the owner-scoped cancellation/release APIs when the view is gone.

Hosts may provide validated intrinsic geometry before decode/upload completes:

```elisa
UiResources::set_intrinsic_size(logo, 128.0, 72.0)
```

The dimensions are bounded, retained with the live logical generation, preserved
across `retry`, and cleared by `dispose`/`reset`. Presentation uses an intrinsic
dimension only when the corresponding `Options.reserved_width` or
`reserved_height` is exactly zero, so an explicit reservation always wins.
Retained widgets carrying the same generation-bound image reference also use
the dimensions as their automatic preferred size; metadata changes invalidate
layout, and stale references cannot read dimensions from a replacement
generation. This keeps loading placeholders and retained image geometry stable
without giving a backend ownership of layout metadata.

`snapshot()` returns bounded counts for the total live records and each
loading/ready/offline/denied/failed/cancelled state, plus the sticky overflow
flag. Diagnostic consumers can use that aggregate without inspecting resource
handles or keeping a native shadow table.

The fixed 128-record table and 256-byte logical identifier limit are deliberate
bounded behavior for native and Wasm tests. `overflowed` reports exhaustion;
identifiers must also follow the SDK's relative virtual-path shape: no absolute
prefix, empty/`.`/`..` component, control byte, drive prefix, URL scheme, or
backslash. Invalid or oversized identifiers return `resource_invalid()` and do
not create a record; the host remains the final authority when resolving the
package map. Use `resource_is_valid()` for stale-safe checks and
`resource_key_matches()` for bounded diagnostics.

## Presentation policy

`src/widgets/ui_resource_presentation.elisa` keeps the user-facing mapping out
of every backend. `UiResourcePresentation::default_options` supplies reserved
geometry and placeholder/fallback colors for generic, image, font, and document
resources. `record(handle, options)` returns a read-only snapshot containing:

- the display state (`Placeholder`, `Loading`, `Ready`, `Offline`, `Denied`,
  `Failed`, or `Cancelled`);
- independent network/decode/upload progress and whether a progress indicator is
  currently appropriate;
- after decode reaches 100%, the standard loading bar follows renderer-upload
  progress rather than appearing complete before the resource is usable;
- placeholder/fallback visibility, retry availability, and interaction state;
- accessible status/alert role, stable title/detail/help copy, and an explicit
  typed action (`Cancel`, `Retry`, or `None`);
- reserved size that can be used before intrinsic metadata or decoded bytes
  arrive.

`perform_action(record)` is the application-control path: it rechecks the live
generation and the record owner's lease before applying the snapshot's action.
Cancel is offered only while that owner observes a pending request; it releases
only that owner's lease, leaving coalesced work alive for other observers.
Retry is offered only for offline, denied, and retryable transport failures,
and returns the replacement generation that the caller must retain. A stale
snapshot cannot cancel a completed request or retry a second time. The lower
level `retry` and `cancel` helpers remain available; `cancel(handle)` cancels
the coalesced operation globally, while `cancel_record(record)` releases only
the record owner's lease. The presentation layer never starts a fetch by
itself. Failed resources carry a
typed `FailureKind`: `RetryableTransport` permits retry, while `Corrupt` and
`Incompatible` remain terminal until a new package/resource identity is
selected. The record's status role/copy and action label can feed retained
labels, buttons, and accessibility metadata consistently across backends.
This keeps offline/denied states recoverable without retry loops and lets a host
render the returned record with native, SDL, or hosted primitives.
An offline presentation can retain partial transfer fractions for diagnostics,
but hides the loading indicator; only an explicit retry starts a fresh
generation with progress reset.

For common assets, `UiResourcePresentation::request_image`, `request_font`, and
`request_document` combine the idempotent logical request with the appropriate
default presentation options and return a `Record` immediately. The generic
`request`/`request_kind` forms accept application-specific options while keeping
the same coalescing and typed-handle lifetime rules.

When visibility is known at request time, `request_image_with_demand`,
`request_font_with_demand`, `request_document_with_demand`, or the generic
`request_with_demand` combines the logical request with one demand hint and
returns a record containing the requesting owner, `demanded`, and aggregate
`demand_priority`. Repeating the helper for a live key adds/reuses that owner's
lease and updates only that owner's priority. `clear_demand(record)` releases
only that record owner's hint; it does not cancel or dispose the logical
resource.

`paint(box, record, options)` emits the backend-neutral placeholder, decoded
progress strip, or fallback card (including its diagnostic mark) through the
ordinary `UiCore` command list. It emits no command for `Ready`, leaving the
verified resource's image/font/document rendering to the host. Thus a backend
does not need a resource-state switch of its own.

`UiResourceComponent::build(parent, handle, owner, options)` composes the
record into an ordinary retained content well plus status/detail/progress/action
controls. The well reserves the record's declared/intrinsic size, clears its
image identity until `Ready`, and binds an image using the exact resource
slot/generation when ready. Call `refresh(view)` after asynchronous progress or state changes; call
`perform_action(view)` from the app's button event and retain its returned view
so retries use the fresh generation. `rebind(view, replacement)` explicitly
keeps the retained controls while adopting a new owner-leased resource handle.
Call `set_visibility_demand(view, visible, priority)` when the viewport changes
whether this component should influence host scheduling. The hint is scoped to
this owner's lease, never starts a fetch, and coalesces with other owners by
maximum priority. Retry/rebind carries a visible hint to a pending generation;
ready, cancelled, and non-retryable terminal states release it.
A cancel detaches that component if other
owners still need the shared request, while cancellation of the final owner
leaves a visible cancelled status. After ordinary retained painting,
`paint_content(view)` draws the framework placeholder or failure fallback over
the well; a ready image remains a normal retained draw for the backend to
resolve. `publish_accessibility(view, frame)` binds
the status/alert, detail, help, and current action to the same retained widget
identities. No host resource or native view pointer crosses the component API.

The hello reference app now builds this retained component around a reserved
180×48 image well. It reuses the component's retry action and explicitly rebinds
the retained controls when a new resource generation replaces a cancelled or
ready one. Long showcase content lives inside a vertical scroll viewport so the
well's reservation is not compressed by the rest of the page. The app-level
workflow checks placeholder/fallback geometry, progress visibility,
stale-image removal on retry, generation rebinding, and the ready draw identity
at desktop and phone viewport sizes. A headless host-operation fixture also
binds an operation token to this component, advances transport/decode/upload
progress independently, and verifies completion binds the same ready image
generation and releases its visibility hint. The host remains responsible for binding
decoded pixels to the same slot/generation before rendering and calling the
example's `renderer_refresh()` after asynchronous state/progress changes.
