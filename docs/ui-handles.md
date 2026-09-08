# Typed widget handles

`src/widgets/ui_handles.elisa` is the small facade for the application-facing
typed-handle layer over the allocation-free `UiFlat` widgets. Its implementation
is split into `ui_handles_types.elisa` (identity and tree lifetime),
`ui_handles_build.elisa` (constructors), `ui_handles_style.elisa` (mutations and
queries), and `ui_handles_input.elisa` (interaction, editing, layout, and
painting). The facade keeps the old index functions available for compatibility,
but a normal application can retain a small `UiHandles::Handle` value instead:

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

`button_accessible` is an opt-in convenience constructor that derives the
button's minimum height from `UiTheme::scaled_metrics`, including high-contrast
and large-text preferences. The explicit-size `button` constructor remains
application-owned and unchanged.

Use `handle(event)` to forward the portable event stream, `hit`/`cursor_at` for
pointer policy, and `activate`/`adjust`/`radio_move` for accessibility actions.
Text composition and editing (`insert_text`, `replace_text`, marked text,
clipboard actions, and undo/redo) remain in Elisa; native adapters only forward
their protocol facts. Queries such as `value`, `selected`, `text_value`,
`is_focused`, and `scroll_offset` return neutral values for stale handles.

At the legacy Elisa `app_widget_event(widget, event)` seam, use
`event_is(event, UiConst::WidgetEvent.Change)` and
`callback_matches(widget, handle)`. These keep event ordinals and callback
identity checks typed at the application boundary. The optional C app adapter
converts that internal slot exactly once to an opaque `elisa_ui_widget_handle`
token carrying the tree lifetime; C code stores and compares the token but
never decodes a retained-arena index. A reset/rebuild invalidates old tokens.

`parent`, `first_child`, and `next_sibling` keep tree traversal typed. Theme
tokens are available through `theme`/`set_theme`; selection and marked-text
ranges are exposed in UTF-16 units, with `selected_text` applying the secure
field privacy rule. `overflowed` reports fixed-arena exhaustion so an app can
render an explicit recovery state instead of silently losing a subtree.

Applications that persist control state can opt into
`src/widgets/ui_handles_persistence.elisa`. It includes the base handle facade
and adds `UiHandlesPersistence::put_text`, `put_value`, and `put_selected`, plus
matching restore functions and the bounded `UiState` blob operations. Secure
text handles are rejected for both save and restore, and all other operations
require a live handle of the matching widget kind.
