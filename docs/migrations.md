# Migrations

This records the intentional versioned changes an existing application or host
may need to make. The framework's own API version is `UiBuild::VERSION_*`
(currently `0.1.0`); the C boundary's packed version is
`ELISA_UI_ABI_VERSION` in `include/elisa_ui.h` (currently `1.2.0`). The
tested platform/profile and toolchain scope is listed in the
[support matrix](support-matrix.md).

## Application callbacks and backend entrypoints

The application callback contract remains the top-level `app_init`,
`app_event`, `app_text_input`, `app_text_editing`, and `app_frame` functions;
`app_widget_event` is also required when the app uses the widget callback path.
There is no replacement `UiApp` entrypoint in this release. Keep application
logic in the existing callbacks; select the host by including its backend entrypoint
(`native_main.elisa`, `wapp_main.elisa`, or the corresponding AppKit, UIKit,
Android, GTK, or Win32 entry file). See the callback signatures and minimal
backend example in [Getting started](getting-started.md).

This migration is intentionally a no-op for callback names and signatures: an
older app does not need to rename them to use the current backends. The
shared `examples/hello/app.elisa` demonstrates top-level forwarding adapters
around namespaced `HelloApp` lifecycle/input methods, as described in
[Getting started](getting-started.md). A reusable framework-level
`UiApplication` registration API has not been introduced. The
ergonomic application-wrapper and compatibility-adapter work remains a
separate, unfinished plan item.

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
major difference is incompatible; minor and patch changes preserve existing
wire records and functions. Hosts must call `elisa_ui_abi_version()` before
stateful calls. A program that uses a function introduced in ABI 1.2 must also
require major version 1 and minor version at least 2; checking only the major
is sufficient only when the program sticks to the functions it already knows.
ABI 1.2 adds scroll viewports and uniform vertical/horizontal virtual lists,
secure text-field construction, input-value replacement, and UTF-8-byte
selection setters/getters. Scroll setters report whether the clamped offset
changed. Selection getters return ordered start/end positions and do not retain
anchor direction. Programmatic input replacement is distinct from changing a
control's visual caption and may synchronously emit a `Change` widget callback.
Secure fields accept input replacement but deny value, length, selection, and
copy-out readback through this C boundary. See the declarations and exact
failure behavior in [`include/elisa_ui.h`](../include/elisa_ui.h) and
[Optional foreign-language bindings](ui-bindings.md).

A safe Rust wrapper (`bindings/rust/elisa_ui.rs`) and a linked
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
- Overflow defaults to `Compress`, preserving the historical squeeze behavior.
  `Clip` and `Visible` preserve child minima and differ in whether underflow is
  clipped to the content box or allowed to paint beyond it. Review
  [`docs/ui-constraints.md`](ui-constraints.md) before opting into a different
  policy; fractional logical geometry is rounded only at the backend boundary.

## Proposed APIs

Any API labeled **proposed** in a design document is not part of this contract
until code, tests, and pinned-compiler support exist. The runnable examples and
the `test/*_test.elisa` corpus are the authority for what is actually shipped.
