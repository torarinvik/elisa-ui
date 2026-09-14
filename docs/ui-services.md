# Services: portable permission and picker results

`UiServices` ([src/widgets/ui_services.elisa](../src/widgets/ui_services.elisa))
owns the application-visible state for operating-system consent and picker
flows. It is the mobile/desktop counterpart to `UiFeatureView` and
`UiResources`: the host performs the native request, and the framework records
and presents a typed result without ever manufacturing authority.

## What the framework owns

- A bounded table of service records keyed by `ServiceKind` and an
  application-supplied owner, with generation-checked handles.
- The consent state machine:
  `Unrequested → Requested → {Granted, Denied, Restricted, Unavailable, Failed, Cancelled}`.
- The picker state machine:
  `Idle → Presenting → {Selected, Cancelled, Failed, Unavailable}`.
- The anti-prompt gate (`can_prompt`) and the picker re-presentation gate
  (`can_present`).
- Independent consent and picker failure facts (`consent_failure` and
  `picker_failure`); the older `failure` accessor remains the most recent
  workflow failure for compatibility.
- Invalidation of paint and semantics whenever a state changes.

## What the host owns

- The native permission dialog, OS settings, and the picker UI itself.
- Mapping a logical `selection_id` to verified bytes or a renderer resource.
  A selected result is never a native path or URL.
- Reporting facts: `resolve_consent` for a prompt result, `sync` for a
  settings change observed on resume, and `resolve_picker` for a picker result.

## Anti-prompt policy

Once a service is `Denied`, `Restricted`, or `Unavailable`, `can_prompt` stays
false and `begin_prompt` refuses. A redraw or rebuild therefore cannot re-raise
a dialog the user already answered. Only an explicit host `sync` (the user
changed the setting outside the app) can turn the state green. `Failed` with a
retryable failure and a user-dismissed `Cancelled` prompt may ask again, which
is how an "explain, then ask once more" flow is expressed.

Pickers are different: they are user-initiated every time, so any terminal
picker state may `present_picker` again. A picker is not an OS "don't ask
again" grant.

## Result coherence

`resolve_consent` and `sync` reject contradictory facts: `Granted` requires
`Unknown` failure, `Denied` requires `Denied`, `Restricted` requires
`Restricted`, `Unavailable` requires `Unavailable`, and `Failed` requires a
retryable or unknown failure. `resolve_picker` rejects an empty
(`selection_id == 0`) "selected" result, so a cancelled picker cannot be
mistaken for a successful empty one. Consent and picker errors are recorded
separately: a picker operation can no longer erase the retryable consent
failure that controls `can_prompt`.

## Lifetime

`dispose_owner(owner)` releases every record for an application view, so a
late host callback cannot mutate a recycled slot. `back(handle)` consumes a
presenting picker but never dismisses a consent dialog the framework does not
own.
