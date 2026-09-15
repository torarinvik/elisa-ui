# Optional foreign-language bindings

The stable foreign-language boundary is [`include/elisa_ui.h`](../include/elisa_ui.h).
It carries scalar events, counted borrowed UTF-8 text, normalized viewport
facts, and opaque generation-scoped widget tokens. Call
`elisa_ui_abi_version()` before any stateful call and reject a major mismatch.
The boundary is synchronous and single-threaded; hosts must serialize calls on
one UI-owner OS thread, including callbacks.

The repository keeps three optional consumers of that same boundary:

- C and C++: [`examples/capi`](../examples/capi), checked by
  [`scripts/check_capi.sh`](../scripts/check_capi.sh).
- Rust: [`bindings/rust/elisa_ui.rs`](../bindings/rust/elisa_ui.rs), checked by
  [`scripts/check_rust.sh`](../scripts/check_rust.sh).
- Go/cgo: [`bindings/go/elisa_ui`](../bindings/go/elisa_ui), with a host in
  [`examples/go/main.go`](../examples/go/main.go), checked by
  [`scripts/check_go.sh`](../scripts/check_go.sh).

The Go package owns no retained framework state. Its dispatch functions copy Go
strings into a temporary byte slice before crossing the borrowed C boundary;
the linked Elisa adapter bounds and validates the payload. A Go host that drives
callbacks should lock its UI goroutine to the owner thread with
`runtime.LockOSThread`, and must not retain callback text or event pointers
after the callback returns. `WidgetHandle` is only a nonzero/zero token check;
its representation must not be decoded or persisted across a retained-tree
reset.

These bindings are optional host adapters, not a second widget implementation.
An application using another UI framework does not need to link elisa-ui.
