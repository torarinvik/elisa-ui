# Resource presentation state

`UiResources` is the framework-owned half of on-demand resource loading. It
does not fetch bytes, verify packages, manage a cache, decode images, upload
fonts, or grant capabilities; those remain host/SDK responsibilities. It keeps
the state that a live view can safely present while that work happens elsewhere.

```elisa
include "src/widgets/ui_resources.elisa"

UiResources::reset()
logo: UiResources::Handle = UiResources::request("images/logo", 7)
UiResources::set_progress(logo, network_fraction, decode_fraction)
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
only recoverable denied/offline/failed states.

Network and decode progress are separate normalized fractions. A value of 1.0
for network progress never implies that a resource is ready to paint. State or
progress changes raise `UiCore::Invalidation.Resources` and
`UiCore::Invalidation.Paint`; a host or diagnostic consumer can clear the
resource reason after it has consumed the change.

The fixed 128-record table and 256-byte logical identifier limit are deliberate
bounded behavior for native and Wasm tests. `overflowed` reports exhaustion;
invalid or oversized identifiers return `invalid()` and do not create a record.
