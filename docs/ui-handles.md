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
volume: UiHandles::Handle = UiHandles::slider_labeled(root, "Volume", 160.0, 28.0, 0.5, track, fill, thumb)
password: UiHandles::Handle = UiHandles::secure_text_field(root, "Password", "required", "", 240.0, 32.0, 15.0, foreground, field_fill)
UiHandles::layout(800.0, 600.0)
UiHandles::paint()
```

The shared hello example follows this pattern on SDL3, AppKit canvas, and
WasmBrowser: application state stores handles, and only the legacy callback
boundary converts a callback's widget index with `UiHandles::index`.

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

`slider` and `progress_bar` retain their original caption-less signatures for
source compatibility; `slider_labeled` and `progress_bar_labeled` pass a
caption into the Elisa-owned retained state. `secure_text_field` is the
privacy-preserving text constructor. All control styling, sizing, alignment,
visibility, focus order, selection groups, values, and steps are available as
typed handle setters.

Use `handle(event)` to forward the portable event stream, `hit`/`cursor_at` for
pointer policy, and `activate`/`adjust`/`radio_move` for accessibility actions.
Text composition and editing (`insert_text`, `replace_text`, marked text,
clipboard actions, and undo/redo) remain in Elisa; native adapters only forward
their protocol facts. Queries such as `value`, `selected`, `text_value`,
`is_focused`, and `scroll_offset` return neutral values for stale handles.

`parent`, `first_child`, and `next_sibling` keep tree traversal typed. Theme
tokens are available through `theme`/`set_theme`; selection and marked-text
ranges are exposed in UTF-16 units, with `selected_text` applying the secure
field privacy rule. `overflowed` reports fixed-arena exhaustion so an app can
render an explicit recovery state instead of silently losing a subtree.
