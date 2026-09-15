# Migrations

This records the intentional versioned changes an existing application or host
may need to make. The framework's own API version is `UiBuild::VERSION_*`
(currently `0.1.0`); the C boundary's packed version is
`ELISA_UI_ABI_VERSION` in `include/elisa_ui.h`.

## Legacy index handles → typed handles

Old code built widgets with `UiFlat::*` constructors and stored the returned
`usize` slot. That index is a retained-arena position and can be recycled after
a reset or rebuild.

New code uses `UiHandles::Handle`, which carries a tree generation and fails
closed on a stale value. The migration is mechanical:

- constructors: `UiFlat::button(...)` → `UiHandles::button(...)` (and the other
  builders in `src/widgets/ui_handles_build.elisa`);
- queries: `UiFlat::text_value(index)` → `UiHandles::text_value(handle)`;
- the one remaining bridge from the backend callback, which still delivers the
  legacy `usize`, is `UiHandles::index(handle)`.

The legacy `UiFlat` index API is retained and documented as compatibility; it is
not deprecated in a way that breaks existing sources. New binaries that do not
use `UiIdentity` pay no cost for the generation registry.

## Events: wire ordinals and typed values

Event wire ordinals (`ELISA_UI_EVENT_*`, `UiCore::WireKind`) are stable. Pointer
buttons are a closed five-value vocabulary (`primary`, `secondary`, `middle`,
`back`, `forward`); unknown ordinals are rejected at the boundary and arrive as
`Event.None` rather than as a trap. If you hand-wrote ordinals, use the named
constants instead.

## C ABI

`include/elisa_ui.h` is versioned with `ELISA_UI_ABI_VERSION` (`0xMMmmpp`). A
major difference is incompatible; minor and patch changes preserve the existing
wire records. Hosts must call `elisa_ui_abi_version()` and compare before
sending events. A safe Rust wrapper (`bindings/rust/elisa_ui.rs`) and a linked
example (`examples/rust/rust_host.rs`) consume the same ABI, as does the
optional cgo package in `bindings/go/elisa_ui` and its linked example
(`examples/go/main.go`). `check_capi.sh` and `check_go.sh` exercise the
cross-language boundary against the same Elisa adapter. Go calls are
synchronous and must stay on one UI-owner OS thread (lock the driving
goroutine with `runtime.LockOSThread`); the package does not marshal callbacks
or retain Go pointers.

## Layout semantics

- Box layout distributes remaining main-axis room by `grow` weight; a child's
  `maximum` caps both stretching and weighted growth, and unused growth is
  redistributed rather than left as a gap.
- Individual widgets may add normalized margins that participate in both
  measurement and arrangement; cross-axis alignment supports start, center, end,
  and stretch.
- After the first layout, geometry-affecting mutations are retained as a dirty
  layout and reflow automatically before paint, hit testing, or scroll queries
  against the remembered viewport. Call `layout` explicitly when the viewport
  itself changes.
- Hidden widgets collapse layout space transitively; disabled container state is
  inherited for input, visuals, and semantics without overwriting each child's
  local enabled flag.
- Table columns use `UiTable` for shared widths; tree rows use `UiTree` for
  flattening. Both are additive policies; neither changes existing sizer
  behavior.

## Proposed APIs

Any API labeled **proposed** in a design document is not part of this contract
until code, tests, and pinned-compiler support exist. The runnable examples and
the `test/*_test.elisa` corpus are the authority for what is actually shipped.
