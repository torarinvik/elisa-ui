# Revision-safe asynchronous validation

`UiValidation` stores only visible validation state; the editable value stays
in the widget/application model. Bind a stable field ID once, then associate
each asynchronous request with the revision returned by `begin`:

```text
field = UiValidation::bind(model.email_id)
revision = UiValidation::begin(field)
// host validates the current draft
UiValidation::reject(field, revision, "Not available")
```

The state is explicit: `Idle`, `Validating`, `Valid`, `Invalid`, or
`Unavailable`. A completion for an older revision is rejected, so a late task
cannot replace a newer error, clear a newer message, or roll back user edits.
Messages are allocation-free and bounded to 255 bytes; truncation is exposed
through `message_truncated`. Disposal advances the generation before slot reuse
to make callbacks targeting a recycled view harmless.

Binding, pending, result, clear, and disposal transitions raise shared paint and
semantic invalidations. Adapters do not need a validation-specific redraw path;
they consume the same `UiCore::Invalidation` flags as the rest of the retained
widget state.
