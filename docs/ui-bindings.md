# Optional foreign-language bindings

The stable foreign-language boundary is [`include/elisa_ui.h`](../include/elisa_ui.h),
currently ABI 1.1.0. It carries scalar events, counted borrowed UTF-8 text,
normalized viewport facts, and opaque generation-scoped widget tokens. Call
`elisa_ui_abi_version()` before any stateful call and reject a major mismatch.
The boundary is synchronous and single-threaded; hosts must serialize calls on
one UI-owner OS thread, including callbacks.

## C boundary ownership and failure contract

The packed `ELISA_UI_ABI_VERSION` is `0xMMmmpp`: reject a major-version
mismatch before making stateful calls. `elisa_ui_event` is a flat six-scalar
wire record; it exposes neither Elisa object layout nor internal arena storage.

Text lengths are byte counts, not NUL-terminated string lengths. Payloads are
UTF-8 and may contain U+0000; that remains text, and the ABI has no binary
payload channel. Host pointers are borrowed only until the
synchronous dispatch call returns; Elisa copies text into a bounded staging
buffer of at most `ELISA_UI_MAX_TEXT_BYTES`. Oversized or malformed UTF-8 input
is reduced to the longest valid prefix that fits. Text and event pointers
passed to `elisa_ui_on_*` callbacks are borrowed only until that callback
returns. IME selection positions are Unicode-scalar offsets and are clamped to
the delivered text.

The C functions do not return per-call status codes and there is no error
callback. A null text pointer with a nonzero length, malformed pointer/scroll
geometry, or input rejected by lifecycle policy is ignored; unknown event
ordinals are delivered as `ELISA_UI_EVENT_NONE`. Since event dispatch can be
queued or rejected under bounded-queue pressure, returning from a `void`
dispatch function is not an acknowledgement that the application processed
the event. Calls and callbacks must remain serialized on the UI-owner thread;
the boundary does not marshal worker-thread calls.

`elisa_ui_widget_handle` is an opaque, generation-scoped identity, not an
owning/reference-counted resource handle. Zero is invalid; for builder parent
arguments only, zero means the root insertion point. Nonzero tokens may be
compared while the retained tree is live, but must not be decoded or kept
across a tree reset/rebuild. The C ABI currently supports rows, columns,
counted-UTF-8 labels, buttons, check boxes, radio buttons, sliders, progress
bars, initial-value text fields, caption/state changes, selection and
normalized-value access, text-field focus and bounded UTF-8 readback, liveness
queries, and activation; Rust and Go expose the same operations through typed
wrapper functions. Text-field copy-out writes no terminator and never splits a
UTF-8 sequence. Radio grouping policy remains application-owned. Slider and
progress values are finite and normalized to `[0, 1]`. `elisa_ui_widget_tree_reset`
destroys the whole retained tree and invalidates every old token. The ABI does
not expose individual widget release or separately allocated foreign-owned
resources.
Any future per-widget destruction or owned-resource API requires an explicit
lifetime/release contract and ABI versioning.

`scripts/check_capi.sh` builds and runs the C host against both a static archive
and a native shared library, and checks their actual exported host symbols and
imported callbacks. This is native-link evidence only; it does not establish
WASM component or WIT interoperability, which remains a separate SDK contract.

The repository keeps three optional consumers of that same boundary:

- C and C++: [`examples/capi`](../examples/capi), checked by
  [`scripts/check_capi.sh`](../scripts/check_capi.sh).
- Rust: [`bindings/rust/elisa_ui.rs`](../bindings/rust/elisa_ui.rs), checked by
  [`scripts/check_rust.sh`](../scripts/check_rust.sh).
- Go/cgo: [`bindings/go/elisa_ui`](../bindings/go/elisa_ui), with a host in
  [`examples/go/main.go`](../examples/go/main.go), checked by
  [`scripts/check_go.sh`](../scripts/check_go.sh).

The Go package owns no retained framework state. Its dispatch functions scan at
most `MaxTextBytes`, borrow a valid UTF-8 prefix directly from immutable string
storage, and make no temporary text-buffer allocation; the linked Elisa adapter
copies it into its fixed staging slot before returning. The byte limit is
`ELISA_UI_MAX_TEXT_BYTES` in the header and is tested against the live adapter.
A Go host that drives callbacks should lock its UI goroutine to the owner thread with
`runtime.LockOSThread`, and must not retain callback text or event pointers
after the callback returns. `WidgetHandle` is only a nonzero/zero token check;
its representation must not be decoded or persisted across a retained-tree
reset.

These bindings are optional adapters, not a second widget implementation.
They can build and use a retained-control subset inside an Elisa-authored app,
but do not yet mirror the full `UiHandles` widget catalog (including text
editing/IME operations, scrolling, virtualization, and the broader
styling/interaction surface). An application
using another UI framework does not need to link elisa-ui. The UI-12 exit
remains open until the supported control surface and its teardown/use cases
meet the full foreign-language acceptance matrix.
