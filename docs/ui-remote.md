# Remote rendering and input policy

`UiRemote` is the portable policy layer for a remote UI host. It does not open
sockets, own packets, or retain a framebuffer/video object. The transport host
supplies an `Offer`; Elisa negotiates one presentation representation and keeps
the resulting scale, logical size, connection state, and input sequencing
visible to the application and inspector layers.

Presentation preference is honored when offered. Otherwise the policy falls
back to typed commands, framebuffer, then video, preserving the most
inspectable representation available. Physical dimensions are bounded and
divided by a normalized scale (default `1`, capped at `16`) before they reach
layout. The selected record contains both physical and logical dimensions so a
host can resize without changing widget state.
Viewport conversion is fail-closed: `logical_size()` returns a zero size until
the selection is accepted, so rejected or disconnected offers cannot inject a
plausible layout viewport.

`connect`, `suspend`, `resume`, and `disconnect` form the lifecycle contract.
Each successful connection and disconnect advances a generation; a suspended
or disconnected session exposes `overlay_visible` and rejects application
input. Input sequence numbers are transport-owned, but Elisa rejects zero,
duplicate, and out-of-order submissions and only accepts acknowledgements for
sent sequences. The sticky `stale_input` fact lets a host render a reconnect or
latency diagnostic without maintaining a second policy table.
Malformed acknowledgements (zero, beyond the sent frontier, or older than the
acknowledged frontier) also set that sticky diagnostic before being rejected.

The module is allocation-free and backend-neutral. A future remote adapter may
map the negotiated representation to the SDK's command, framebuffer, or video
channel and forward its events through this contract; no remote host object or
raw pointer crosses into the retained widget framework. `test/remote_test.elisa`
covers negotiation, scale conversion, lifecycle overlays, generation changes,
and input acknowledgement behavior headlessly.
