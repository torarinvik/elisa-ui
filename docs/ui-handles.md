# Typed widget handles

`src/widgets/ui_handles.elisa` is the application-facing builder layer over
the allocation-free `UiFlat` widgets. It keeps the old index functions
available for compatibility, but a normal application can retain a small
`UiHandles::Handle` value instead:

```elisa
include "src/widgets/ui_handles.elisa"

UiHandles::reset()
root: UiHandles::Handle = UiHandles::column(UiHandles::root_parent(), 16.0, 8.0, background)
save: UiHandles::Handle = UiHandles::button(root, 96.0, 32.0, accent, hover, pressed)
UiHandles::set_text(save, "Save", 14.0, foreground)
UiHandles::layout(800.0, 600.0)
UiHandles::paint()
```

The root-parent token is produced by `root_parent()`. A constructor returns an
invalid handle when the parent belongs to an older tree or the fixed arena is
full; check `UiHandles::is_valid` before retaining or using it. Mutations and
focus requests on stale handles are no-ops/false, and `widget` returns no
record. `UiFlat::reset` advances the retained-tree lifetime, so a slot reused
by a rebuild cannot be accidentally modified through an old handle.

The handle contains only a u32 widget slot and a u32 tree lifetime. It does not
expose the retained row, arena storage, or native backend object. The
`UiHandles::index` function is an explicit escape hatch for adapters that must
call the legacy index API; stale values map to `UiFlat::NONE`.
