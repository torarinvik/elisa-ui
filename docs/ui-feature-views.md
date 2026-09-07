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
bounded Elisa-owned storage. A nonzero host token is required before polling;
poll results are accepted only for the current loading generation. Terminal
states (`Ready`, offline, denied, incompatible, and failed) cannot be revived
in place. `retry()` rotates the generation and returns a replacement handle,
so late host results cannot update a newly requested feature.

The visible states are `Requested`, `Loading`, `Ready`,
`UnavailableOffline`, `Denied`, `Incompatible`, `Failed`, and `Cancelled`.
`FeatureFailureKind` distinguishes retryable transport errors from corrupt,
incompatible, denied, and offline results. `dispose_owner()` releases all
feature views owned by a dismissed screen; the old handles then fail closed.
`cancel()` keeps the host activation token readable until the host has
acknowledged deactivation, while a subsequent request rotates the generation
and clears that old token.

`UiInspector::Frame.features` exposes bounded counts for diagnostics. State
changes invalidate paint and semantics so loading/error/cancellation UI can be
updated without a backend shadow model. The module has no native pointers and
is safe to use with native, hosted, and deterministic harness backends.
