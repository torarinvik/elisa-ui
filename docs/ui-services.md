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

## Native coverage

The UIKit and Android adapters currently implement user-triggered Camera and
Microphone consent. UIKit delegates to AVFoundation and resynchronizes both
authorization facts when the app becomes active. Android requests the matching
runtime permission, returns the result through a bounded owner-thread queue,
and synchronizes current permission facts on resume. Android also preserves
the prior-prompt fact across process recreation, so a fresh in-memory record
does not bypass the shared no-repeat policy. Both paths enter the shared
`UiServices` state machine; they do not grant access in Elisa code.
`test/uikit_services_test.elisa` and `test/android_services_test.elisa` cover
the adapter-to-state transitions, stale callbacks, failure handling, and
unrelated-state preservation. Android also implements user-triggered Photos
and Files pickers. It copies selected content into a bounded host-owned store
(16 MiB per selection, 32 MiB total, 16 selections), reports only an opaque
logical ID and MIME-derived kind, and exposes bounded reads of at most 64 KiB
per call. Call `UiAndroidServices::release_selection` when finished; release
frees the host bytes and clears the shared selected result. Re-presenting a
selected Android picker also releases its previous content first. Release a
selection before disposing its owner; generic owner disposal cannot call a
platform-specific content store. The Photos picker accepts images only.
`examples/android_services_smoke/android_main.elisa` provides a tap-driven
runtime smoke for both picker paths. UIKit now has matching PhotosUI and Files
adapters with the same bounded, opaque selection/read/release contract, plus a
tap-driven `examples/uikit_services_smoke` app. Both UIKit apps and the picker
shim cross-build. `scripts/check_uikit_services.sh` rebuilds the smoke app,
creates a dedicated simulator, and drives PhotosUI and Files with XCUITest;
the selected image and text content are read through the bounded API and
explicitly released. The check is headless and does not require Simulator.app.
Other service-kind picker adapters remain unimplemented.

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
retryable or unknown failure. A selected picker result requires a nonzero
opaque ID and a supported `ServiceSelectionKind`: `Image`, `Audio`, `Video`,
`Text`, `Application`, or `Other`. `Unknown` is reserved for non-selected
results, and unrecognized enum values are rejected. This prevents an empty
selection or malformed host fact from appearing as valid selected content.
Consent and picker errors are recorded separately: a picker operation can no
longer erase the retryable consent failure that controls `can_prompt`.

## Lifetime

`dispose_owner(owner)` releases every record for an application view, so a
late host callback cannot mutate a recycled slot. `back(handle)` consumes a
presenting picker but never dismisses a consent dialog the framework does not
own.
