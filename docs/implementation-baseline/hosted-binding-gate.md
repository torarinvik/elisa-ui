# WasmBrowser binding migration gate

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._

UI-01 keeps handwritten hosted record encoding until the SDK migration/version
gate provides an Elisa binding that represents the complete UI contract. The
current `wasmbrowser:window@0.1.0` adapter includes generated host import
declarations, but those declarations still accept raw pointer/count spans:
`host_present_commands` receives `void&` plus a count, and
`host_present_semantics` receives a C-string pointer plus a byte count. Those
signatures identify the ABI edge; they do not provide typed Elisa values for
the records carried across it.

The SDK's Elisa `render_buffer.elisa` helper constructs the canonical
`RenderCommand` bytes, but it currently covers tags 0–5 (clear, rectangle,
circle, triangle, line, and text). elisa-ui also emits image tag 6, so swapping
in that helper would silently omit a live command. The generated foreign Rust
`HostRenderCommandWire` API is not a generated Elisa binding and cannot be
called from the UI guest.

The versioned accessibility profile has a typed WIT `semantic-node` record,
but its current Elisa import is likewise a raw node pointer/count plus a
canonical result area. Its node shape does not yet carry every field in the UI
snapshot, including revision, text selection, range, and collection-position
metadata. Treating it as a drop-in replacement would lose published semantic
state.

Before retiring `ui_wasmbrowser_runtime.elisa`'s local encoders, all of these
conditions must hold:

- SDK/WasmBrowser contract versions and the exact compiler/SDK/host tuple are
  pinned together, with the migration gate passing from a clean source state.
- An Elisa-facing SDK adapter represents every UI command variant, including
  images, and the complete semantic-node payload without changing old-host
  decoding behavior or silently discarding fields.
- Conformance fixtures validate every command discriminant and non-zero
  payload, semantic relationships/text/ranges, bounds and ownership through
  the real component host—not only by compiling a guest.
- The ordinary Wapp package and runtime gates pass using that same pinned
  tuple; only then can the UI replace its offsets with SDK-owned typed calls.

Until then, keep the encoder private to the WasmBrowser adapter, document its
wire version, and do not claim that generated import declarations alone have
completed the typed-binding migration.
