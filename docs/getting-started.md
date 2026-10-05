# Getting started

This walks through the shape of an elisa-ui application and points at the
runnable reference for each feature. Every snippet here corresponds to code in
[examples/hello](../examples/hello), which is the same source built for native,
AppKit, UIKit, Android, and the hosted WasmBrowser profile.

## Application module and compatibility callbacks

Keep application behavior in a named module; the required top-level `app_*`
functions are a compatibility adapter for the existing native and hosted
backend contract. Physical keys, committed UTF-8 text, and IME composition
remain separate typed paths:

```elisa
# The application module owns behavior; platform entrypoints keep these names.
def app_init() -> void:
    HelloApp::init()

def app_widget_event(widget: usize, event: i32) -> void:
    HelloApp::widget_event(widget, event)

def app_event(event: UiCore::Event) -> void:
    HelloApp::event(event)

def app_text_input(text: sview) -> void:
    HelloApp::text_input(text)

def app_text_editing(text: sview, selected_start: i32, selected_length: i32) -> void:
    HelloApp::text_editing(text, selected_start, selected_length)

def app_frame() -> void:
    HelloApp::frame()
```

When using `UiHandles`, also implement the optional `app_widget_event(widget:
usize, event: i32)` adapter and immediately convert event integers through
`UiHandles::event_is`; the `HelloApp` example shows typed event comparisons and
generation-checked handles. See [examples/hello/app.elisa](../examples/hello/app.elisa)
for the complete, runnable version. A reusable framework-level `UiApp`
registration API is still an open design item; this adapter pattern does not
claim that migration is complete.

The platform entrypoint remains a small backend selection, not application
logic:

```elisa
include "../../src/platform/sdl3/ui_sdl3_flat.elisa"
include "app.elisa"

def main() -> i64:
    return UiSdl3::run("Elisa UI - hello", 800, 600, 0)
```

## Build the view with typed handles

`UiHandles` builders own geometry, layout, hit testing, focus, editing, and
painting. The application stores `UiHandles::Handle` values, never raw arena
indexes, so a stale handle fails closed instead of touching recycled state:

```elisa
root: UiHandles::Handle = UiHandles::panel(UiHandles::NONE, UiConst::Axis.Column, 16.0, 12.0, background)
title: UiHandles::Handle = UiHandles::label(root, "Hello", 22.0, ink)
UiHandles::set_grow(title, 0.0)
action: UiHandles::Handle = UiHandles::button(root, 120.0, 36.0, idle, hover, pressed)
UiHandles::set_text(action, "Press me", 15.0, ink)
UiHandles::set_grow(action, 1.0)
```

`UiHandles::parent`, `UiHandles::index`, and `UiHandles::event_is` are the
escape hatches for the legacy callback seam; ordinary code stays in typed
handles. See [docs/ui-handles.md](ui-handles.md).

## Persist application state

`UiState` is an explicit, bounded, versioned snapshot hook. It serializes only
application-owned numeric IDs and values — never framework handles or pointers.
`UiHandlesPersistence` binds ordinary text, numeric, and selection controls to
those IDs and rejects secure fields and stale handles:

```elisa
# save
UiHandlesPersistence::begin()
_ = UiHandlesPersistence::put_text(project_field, STATE_PROJECT)
written: usize = UiHandlesPersistence::copy_to(blob, capacity)
# restore
_ = UiHandlesPersistence::restore(blob)
_ = UiHandlesPersistence::restore_text(project_field, STATE_PROJECT)
```

See [docs/ui-state.md](ui-state.md) and
[examples/hello/state.elisa](../examples/hello/state.elisa).

## Load optional resources without blocking

The host owns verified bytes, caching, and decoding; the framework owns the
visible state and the demand tied to view lifetime. `UiResources` runs a bounded
state machine (`Unrequested → Requested → Ready` and the offline/denied/failed
exits), and `UiResourcePresentation` maps it to placeholder/loading/ready/
fallback records with reserved geometry and retry affordances:

```elisa
record: UiResourcePresentation::Record = UiResourcePresentation::request_image("hero.webp", owner)
# reserve geometry from declared or intrinsic metadata
_ = UiResources::set_intrinsic_size(record.handle, 320.0, 200.0)
# later, from a host callback:
_ = UiResources::set_progress(record.handle, network, decode)
_ = UiResources::set_state(record.handle, UiResources::State.Ready)
```

The `Record` carries placeholder/loading/ready/fallback presentation; paint it
with `UiResourcePresentation::paint(box, record, options)`.

See [docs/ui-resources.md](ui-resources.md) and
[examples/hello/resource_demo.elisa](../examples/hello/resource_demo.elisa).

## Validate asynchronously

`UiValidation` keeps pending/valid/invalid/offline states with bounded messages
and revision-checked completions, so an out-of-order result cannot overwrite a
newer edit. [examples/hello/validation.elisa](../examples/hello/validation.elisa)
drives an invalid-to-valid project-name edit through the public API.

## Accessibility is not an afterthought

Every retained widget emits a portable semantic node from the same state used
for layout and input, so painting, hit testing, and assistive navigation agree.
`UiHandles` builders for controls set role and value; `Status`/`Alert` nodes are
live regions. On AppKit and UIKit the framework maps those roles to native
accessibility objects. See [docs/ui-semantics.md](ui-semantics.md).

## Run it

```sh
scripts/build_native.sh hello
./build/hello_native

# headless smoke (no window shown)
SDL_VIDEODRIVER=dummy ELISA_UI_SMOKE_FRAMES=1 ./build/hello_native

# hosted WasmBrowser profile
export PATH="$HOME/.cargo/bin:$PATH"
scripts/build_wapp.sh hello
wasm-browser inspect build/hello.wapp
```

AppKit canvas, UIKit, Android, GTK, and Windows entrypoints are siblings of
`native_main.elisa`; the README's Build section lists each gate. For the larger
multi-page reference, see [examples/showcase](../examples/showcase).
