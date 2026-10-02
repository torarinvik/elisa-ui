# Optional feature views

`UiFeatureView` is the framework-side presentation state for an optional code
feature. It does not download, verify, link, or unload a component. Those
operations remain owned by the SDK and WasmBrowser host. The application asks
the host to activate a `(feature_id, interface_version, package_version)`
tuple, then reports the returned opaque activation token through Elisa.

```elisa
feature = UiFeatureView::request(7, 1, "2.0.0", owner_id)
UiFeatureView::activate(feature, host_activation_id)
UiFeatureView::resolve(feature, host_activation_id,
    UiFeatureView::FeatureState.Ready, UiFeatureView::FeatureFailureKind.Unknown)
```

Requests are idempotent for the same identity and copy the package version into
bounded Elisa-owned storage. Multiple owners requesting the same tuple share
one activation handle, but receive independent bounded leases. `owner_count()`
and `owns()` inspect that set; `owner()` remains a compatibility projection
of its first owner. Rebuilding a screen for the same owner does not create a
second lease. A nonzero host token is required before polling; poll results are
accepted only for the current loading generation. Terminal states (`Ready`,
offline, denied, incompatible, and failed) cannot be revived in place.
`Ready` retains its activation token because the component remains live and
needs that token for later deactivation. Every other accepted terminal result
completes the activation operation and clears the token; offline, denied,
incompatible, and failed results can therefore be retried without abandoning a
live host token. `retry()` rotates the generation and returns a replacement
handle, so late host results cannot update a newly requested feature.

`resolve()` accepts only a terminal result (a repeated `Loading` report is
rejected) and requires failure metadata to match the terminal state: offline,
denied, and incompatible results use their corresponding failure kind, while a
successful result uses `Unknown`. This keeps retry and error presentation
decisions deterministic at the framework boundary. A successful `Ready`
result preserves its activation token; a non-Ready terminal result consumes it.

An activation request can also be rejected before the host grants a token.
`reject_activation()` accepts that result only from `Requested` with no token,
so it cannot fabricate an activation ID or race a stale poll. Generic
unavailability is kept distinct from offline failure and is presented as a
host/package limitation rather than an automatic retry.

The visible states are `Requested`, `Loading`, `Ready`,
`UnavailableOffline`, `Denied`, `Incompatible`, `Failed`, and `Cancelled`.
`FeatureFailureKind` distinguishes retryable transport errors from corrupt,
unavailable, incompatible, denied, and offline results. `dispose_owner()` releases every
lease for a dismissed screen without disturbing a shared activation. When the
final owner leaves a pending Loading or live Ready activation with a host
token, the record becomes a cancelled tombstone and remains valid until the host
acknowledges deactivation. Direct `dispose(handle)` follows the same safety
rule: it releases every owner lease but preserves any live token in a cancelled
tombstone. A record with no live token is cleared immediately. The host then calls
`acknowledge_deactivation(handle, activation_id)`; both the handle generation
and original token must match before Elisa clears the token and releases an
ownerless slot. A matching request is rejected while that acknowledgement is
outstanding, so it cannot orphan the host token. Thus only pending or Ready
activations with live tokens await deactivation acknowledgement; a final owner
can release a non-Ready terminal record immediately because `resolve()` has
already consumed its activation token.

`cancel(handle)` explicitly cancels the shared operation. For one-view-at-a-time
teardown, `cancel_for_owner(handle, owner_id)` removes just that owner's lease;
the operation is cancelled only after its final owner leaves. `cancel_owner()`
applies that policy to every feature owned by a screen.
`reset()` also releases all owner leases and clears feature payloads, but it
does not discard a nonzero host activation token. Such activations become
ownerless cancelled tombstones and remain enumerable through
`deactivation_count()` / `deactivation_at()` until the host acknowledges each
`(handle, activation_id)` pair. This lets stop/restart retire UI state without
orphaning a live component or losing its deactivation key.

For an application screen, `view(handle)` returns a stable projection with the
current state, failure kind, activation token, and a single explicit action.
`action()` reports `Cancel` while requested/loading and `Retry` for retryable
terminal states. `back(handle)` consumes back by cancelling the shared
in-flight activation and returns false for terminal states, allowing the
application to pop the screen or let the platform handle navigation. Use
`cancel_for_owner()` when only one coalesced observer is leaving. This keeps
cancellation and back behavior accessible without making the host aware of
widget or arena internals.

`UiInspector::Frame.features` exposes bounded counts for diagnostics. State
changes invalidate paint and semantics so loading/error/cancellation UI can be
updated without a backend shadow model. The module has no native pointers and
is safe to use with native, hosted, and deterministic harness backends.

`UiFeaturePresentation` maps each live state to accessible status or alert
copy, recovery guidance, action choice, and a small tone-coded background. It
publishes the state as a `UiCore` semantic node while leaving labels, focus,
keyboard behavior, and action controls in the application's ordinary retained
widget tree. Semantic and action identities are `UiHandles::Handle` values;
stale tree generations are rejected, and actionable feature semantics must
target a retained Button rather than a raw widget index or non-action label.
`perform_action(handle, owner_id)` releases only that owner's loading lease, so
cancelling one screen cannot stop a coalesced activation still observed by
another. Retry returns the rotated handle; choosing a different package
version remains an explicit application decision.

`UiFeatureComponent::build(parent, handle, owner, options)` is the reusable
retained parent-owned surface. `refresh(view)` copies bounded feature content
into ordinary labels and buttons. Each retained view captures the content
sequence and action key it rendered; `content_action_key(view)` returns zero
when the live snapshot has advanced or been cleared before refresh, so an old
visible label cannot dispatch a newer or retired action. After refresh, the copied label and matching
action key become available together. No feature-owned callback or widget
identity is accepted. `perform_action(view)` updates the retained generation
after retry, detaches a cancelled co-owner, and preserves a live cancellation
tombstone until host acknowledgement. `dismiss(view)` releases the owner's lease; a
Ready feature with a live activation token remains a tombstone until the host
acknowledges deactivation, so the UI never claims executable unloading.
`publish_accessibility(view, frame)` connects status/alert copy to the retained
recovery action. `feature_component_test` covers these lifecycle rules, while
`feature_sdk_composition.elisa` feeds typed SDK activation facts and a copied
panel through this retained wrapper. The app still owns the SDK/host activation
adapter and dispatches the returned action key in its own code.

## Parent-owned content snapshots

When a ready feature has content to show, the SDK/host adapter can copy one
versioned panel snapshot into the UI model:

```elisa
UiFeatureView::publish_content(feature, host_activation_id, sequence,
    "Diagnostics", "Recent events and runtime health.", 41, "Open events")
panel = UiFeatureView::content(feature)
title = UiFeatureView::content_title(feature)
```

The title, body, and action label have fixed byte limits (95, 383, and 79
bytes) and must be valid UTF-8. A nonzero action key requires a label; key zero
means no action. The monotonically increasing sequence rejects replay and
out-of-order updates. Clearing the visible content retains that sequence
watermark; disposing or retiring the feature clears both. Text getters return
views into UI-owned storage and remain valid until the next update or clear.

The action key is data, not a callback or widget identity. The parent app maps
it to its own behavior and builds ordinary `UiHandles` controls from the copied
text; no component-memory pointer or foreign widget handle is accepted. The
retained component returns zero rather than a newer, unseen key if content is
published between paints; the app can dispatch only the key matching the
currently rendered sequence, and refresh adopts the next pair atomically. The
SDK/UI composition fixture exercises this retained-tree path, and the hosted
feature smoke checks that the same content contract survives Wasm compilation
and activation teardown. These fixtures do not yet demonstrate a real SDK
feature returning that panel through a production adapter or a shell rendering
its registered surface; that remains end-to-end integration work.
