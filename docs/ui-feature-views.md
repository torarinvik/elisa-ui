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

The visible states are `Requested`, `Loading`, `Ready`,
`UnavailableOffline`, `Denied`, `Incompatible`, `Failed`, and `Cancelled`.
`FeatureFailureKind` distinguishes retryable transport errors from corrupt,
incompatible, denied, and offline results. `dispose_owner()` releases every
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
