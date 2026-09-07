# elisa-ui

A cross-platform UI framework written in **Elisa**, targeting native desktop
(SDL3) and [WasmBrowser](../WasmBrowser) in lockstep. A RAD designer tool is
planned on top. Eventually expected to fold into the wasm-browser-sdk.

**The web target is WasmBrowser, not an ordinary browser.** WasmBrowser is a
Wasmtime component host that loads `.wapp` packages whose only payload is
`manifest.json` plus a Wasm component. Nothing here emits JavaScript, an ESM
loader, or TypeScript declarations, and nothing should.

## Architecture

Drawing is **retained**. An app's frame appends to a command batch; the backend
consumes the whole batch at frame end. That is what
`wasmbrowser:window/host@0.1.0`'s `present-commands` takes (one list per frame),
and it is also what the manifest's `hybrid` execution mode requires — remote app
logic with local presentation. SDL3 loses nothing by replaying the batch.

Every file in the library puts its names in a module and is reached as
`Module::name`, so the module supplies the prefix the names used to carry
themselves: `UiCore`, `UiPaint`, `UiRaster`, `UiConst`, `UiWidgets`, `UiFlat`,
`UiHandles`, `UiResources`, `UiControls`, `UiCapi`, and one per backend. The only top-level names anywhere
are the ones something outside Elisa dictates — the `extern`s, the C entry
points, the WIT guest exports, and the platform/application contract below —
because a module member's symbol carries its module and those names cannot move.

- **Core** ([src/core/ui_core.elisa](src/core/ui_core.elisa)) — colour/geometry
  records mirroring the WIT records field-for-field, the `UiCore::Command` batch,
  the drawing API that appends to it, `UiCore::Event` and the input vocabulary
  (`UiCore::Key`, `UiCore::Pad`, `UiCore::PadAxis`). It also exposes typed
  invalidation reasons for layout, paint, semantics, resources, and animation,
  plus a monotonic invalidation sequence for detecting repeated dirty requests.
  Knows nothing about any wire format.
- **Lifecycle** ([src/core/ui_lifecycle.elisa](src/core/ui_lifecycle.elisa)) —
  one typed startup/focus/background/surface/stop state machine shared by the
  headless harness and every backend. It owns session generations and derived
  input/rendering predicates, so platform adapters do not grow divergent
  `running` or `initialized` policy.
- **Application state** ([src/core/ui_state.elisa](src/core/ui_state.elisa)) —
  an explicit, bounded, versioned snapshot hook for application-owned text,
  integer, boolean, and floating-point values. Snapshots contain stable field
  IDs only; framework handles, arena indexes, references, and heap objects are
  never serialized. Malformed, duplicate, truncated, or oversized snapshots
  fail closed.
- **Task lifetime** ([src/core/ui_tasks.elisa](src/core/ui_tasks.elisa)) —
  generation- and token-checked completion records with owner-scoped
  cancellation/disposal, so late host callbacks cannot touch recycled views.
- **Capabilities** ([src/core/ui_capabilities.elisa](src/core/ui_capabilities.elisa)) —
  conservative, typed backend profiles for native windows, custom painting,
  text/IME, clipboard, semantics, hosted presentation, snapshots, scale, and
  deterministic tests. Applications inspect facts instead of branching on OS
  names; the selected profile is visible through `UiInspector::Frame`.
- **Event ingress** ([src/core/ui_event_queue.elisa](src/core/ui_event_queue.elisa)) —
  every backend translates into one bounded FIFO owned by Elisa. Full queues
  reject new events and expose sticky overflow/drop counts through the
  inspector; no native adapter silently replaces authoritative input.
- **Backends** implement the platform side and own the frame loop:
  [sdl3](src/platform/sdl3/ui_sdl3.elisa) (native; the `UiSdl3` module owns
  window/event lifecycle while [ui_sdl3_draw](src/platform/sdl3/ui_sdl3_draw.elisa)
  owns renderer state, SDL_ttf fonts, raster drawing, and the painter; externs
  target system libSDL3 and `UiSdl3::run` drives the loop) and
  [AppKit controls](src/platform/appkit/ui_appkit.elisa) (real native controls;
  [ui_appkit_native](src/platform/appkit/ui_appkit_native.elisa) contains only
  the typed Objective-C/CoreFoundation bridge wrappers while `UiAppKit` owns
  retained control realization) and
  [AppKit canvas](src/platform/appkit/ui_appkit_canvas.elisa) (a custom-painted
  macOS `NSView`; AppKit supplies the window, events, CoreGraphics context and
  accessibility objects and byte-oriented pasteboard primitives through a thin
  Objective-C FFI shim while Elisa owns event translation, visual policy, edit
  command execution, CoreText text shaping, text editing and every rendered
  control). The backend split is deliberate: AppKit controls remain native,
  while custom pixels use the Skia painter in
  [docs/skia-custom-rendering.md](docs/skia-custom-rendering.md) whenever a
  host supplies a pinned Skia surface. `UiSkia` keeps the same command protocol
  and crosses only a narrow C FFI; the current AppKit canvas's CoreGraphics
  path is retained as an explicit fallback until that host integration is
  available, plus
  [wasmbrowser](src/platform/wasmbrowser/ui_wasmbrowser.elisa) (a component
  implementing `world app`; the host drives the loop through the exported guest
  interface, and canonical-ABI encoding is confined to this file; its clipboard
  bridge is also a byte-only Elisa adapter over the WIT host capability). Both
  render real text: WasmBrowser through its host font, SDL3 through SDL_ttf.
- **Responsive layout** ([src/widgets/ui_responsive.elisa](src/widgets/ui_responsive.elisa)) —
  backend-neutral compact/medium/expanded size classes, adaptive axis choice,
  bounded grid-column calculation, and physical touch-target normalization,
  safe-area and software-keyboard insets, and orientation, all driven by
  logical space rather than OS-name branches.
- **Virtual lists** ([src/widgets/ui_virtual_list.elisa](src/widgets/ui_virtual_list.elisa)) —
  bounded visible ranges, edge buffering, item placement, content extents, and
  semantic navigation metadata shared by every backend.
- **Size constraints** ([src/widgets/ui_constraints.elisa](src/widgets/ui_constraints.elisa)) —
  normalized minimum/preferred/maximum extents, bounded resolution, and
  explicit conflict diagnostics for adaptive layouts.
- **Portable semantics** ([docs/ui-semantics.md](docs/ui-semantics.md)) —
  stable semantic relationships and optional numeric ranges are emitted from
  the retained tree and consumed by adapters without duplicating widget state.
- **Dialogs** ([src/widgets/ui_dialog.elisa](src/widgets/ui_dialog.elisa)) —
  bounded modal stacking, typed results, owner-scoped cancellation, portable
  Dialog semantics, and consistent desktop/mobile back behavior with
  stale-handle protection.
- **Back navigation** ([src/widgets/ui_navigation.elisa](src/widgets/ui_navigation.elisa)) —
  one bounded policy for desktop Escape, mobile back, and hosted navigation;
  allow/consume/confirm decisions preserve dirty state and never trap OS
  navigation in a native shim.
- **Gestures** ([src/widgets/ui_gestures.elisa](src/widgets/ui_gestures.elisa)) —
  deterministic bounded touch capture with tap, long-press, drag, pinch, and
  lifecycle cancellation policy shared by native and hosted adapters.
- **Text layout** ([src/widgets/ui_text_layout.elisa](src/widgets/ui_text_layout.elisa)) —
  bounded UTF-8-safe line ranges, newline and whitespace breaks, and
  deterministic long-word fallback independent of the renderer's shaping API.
- **Text input policy** ([src/widgets/ui_text_input.elisa](src/widgets/ui_text_input.elisa)) —
  purpose-driven keyboard/multiline traits with secure-field hardening and
  explicit clipboard and semantic-value privacy.
- **Stable dynamic identity** ([src/widgets/ui_identity.elisa](src/widgets/ui_identity.elisa)) —
  explicit begin/claim/finish transactions preserve keyed generations across
  list and form rebuilds, reject duplicate keys, and invalidate retired items
  safely before slot reuse. It is opt-in so handle-heavy binaries do not pay
  for a registry they do not use.
- **Shared appearance policy** ([src/widgets/ui_theme.elisa](src/widgets/ui_theme.elisa)) —
  one Elisa-side resolver covers system/light/dark palettes, normal/high
  contrast, bounded text scaling, and reduced-motion animation timing for every
  backend. Runtime preferences have a normalized revision/snapshot and
  invalidate layout, paint, and semantics together; the policy is opt-in and
  applications can override resolved tokens. The `UiFlat`/`UiHandles` palette
  adapter ([src/widgets/ui_flat_theme.elisa](src/widgets/ui_flat_theme.elisa))
  applies resolved colors to shared focus, selection, control-mark, and
  scrollbar tokens without overwriting per-widget colors or geometry. Repeated
  palette application is idempotent, so hosts may refresh appearance facts at
  every frame without creating a dirty-loop.
- **Localization and RTL policy** ([src/widgets/ui_localization.elisa](src/widgets/ui_localization.elisa)) —
  locale direction, logical start/end alignment, mirrored coordinates, typed
  plural categories, and a bounded active-locale revision are resolved once in
  Elisa so backends do not drift. Locale changes invalidate layout, paint, and
  semantics together; oversized tags are reported as truncated.
- **Async validation** ([src/widgets/ui_validation.elisa](src/widgets/ui_validation.elisa)) —
  stable field bindings, explicit pending/valid/invalid/offline states, bounded
  messages, owner-scoped teardown, and revision-checked completions preserve
  edits when validation tasks finish out of order.
- **Widgets** ([src/widgets/ui_widget.elisa](src/widgets/ui_widget.elisa)) — a
  retained tree in one fixed array linked by index, box layout, hit testing, and
  hover/press/focus/disabled/selected state. Buttons, radio buttons, check boxes,
  normalized sliders, progress indicators and editable text fields share value
  and accessibility behavior; sliders support dragging, arrow keys and assistive
  increment/decrement actions. Text fields support Unicode input, caret and range
  selection, marked IME composition, 32-step undo/redo, clipboard commands and
  assistive editing.
  Clipboard action validation, secure-field restrictions, and desktop shortcut
  routing live in Elisa; AppKit and SDL expose only their byte pasteboards.
  Left and right modifiers are tracked independently, so releasing one key does
  not cancel a still-held Shift, Control, or Command key.
  Tab and Shift-Tab traverse enabled controls, while Enter/Space activate them.
  SDL and AppKit both preserve left/right Shift, Control, Alt and Super key
  identity, so selection and shortcut state are portable.
  Portable focus lifecycle events release transient capture state when a window
  deactivates without discarding the application’s logical keyboard focus.
  The public `ui_widget.elisa` include is a small facade over separate retained
  state, layout, focus, style, callback, text, scrolling, and painting modules.
  Layout is wxWidgets'
  sizer idea reduced to its load-bearing
  parts: a container distributes its inner box along one axis, each child
  contributes a minimum, and leftover space is shared out by `grow` weight.
  Containers provide padding and sibling spacing; individual widgets can add
  normalized margins that participate in both measurement and arrangement.
  Per-widget cross-axis alignment supports start, center, end, and stretch.
  Optional maximum sizes cap both stretching and weighted growth; unused growth
  is redistributed among uncapped siblings rather than leaving accidental gaps.
  Containers can distribute remaining main-axis room at the start, center, end,
  or between children.
  Keyboard focus order is configurable in Elisa and remains stable by creation
  order when multiple controls share the same rank. The same order drives the
  native accessibility navigation sequence without backend-specific sorting.
  Public retained handles have validity checks and an optional safe lookup for
  data arriving from application or FFI boundaries.
  Checkbox toggling and exclusive radio selection are framework semantics, with
  configurable radio groups shared by pointer, keyboard, accessibility, and
  programmatic activation paths.
  Focused radio buttons follow their group with the arrow keys, wrapping in
  focus order while skipping disabled or hidden peers.
  Scroll viewports bubble wheel input through nested ancestors and support
  Page Up/Down, Home/End, and axis-arrow navigation from focused descendants.
  Slider step size is configurable; arrows and accessibility use one step,
  Page Up/Down use ten, and Home/End move to normalized bounds.
  Measure runs bottom-up, arrange top-down.
  Dynamic label text and typography changes are remeasured before the next
  layout, so localization and live status content cannot retain stale bounds.
  After the first layout, geometry-affecting mutations are retained as a dirty
  layout and reflow automatically before paint, hit testing, or scroll queries
  against the remembered viewport; call `layout` explicitly when the viewport
  itself changes.
  Widgets can be hidden without rebuilding the tree; visibility collapses
  layout space and applies transitively to painting, input, focus, tooltips and
  accessibility.
  Disabled container state is likewise inherited by descendants for input,
  visuals and semantics without overwriting each child's local enabled flag.
  Applications can request or clear focus directly for form validation and
  dialog workflows; ineligible hidden or disabled targets are rejected.
  Public layout metrics are normalized at entry, preventing negative sizes,
  padding, spacing, grow weights or typography from escaping into geometry.
  Fixed arenas expose overflow flags, so capacity mistakes are diagnosable
  rather than silently indistinguishable from missing UI. The read-only
  `UiInspector` projection reports typed hierarchy, bounds/constraints,
  deferred layout and frame-buffer state, matching semantic nodes while
  redacting secure text for diagnostics.
  It also exposes the raw invalidation mask and sequence so tooling can observe
  repeated updates even when a dirty bit remains set, a task snapshot for
  lifecycle diagnostics, and the active locale snapshot (canonical tag,
  direction, revision, and truncation state).
  New application code can use [UiHandles](docs/ui-handles.md) for typed u32
  handles with retained-tree lifetime checks; the older index API remains for
  compatibility and low-level adapters.
- Applications that want to persist control state can opt into
  `src/widgets/ui_handles_persistence.elisa`; its `UiHandlesPersistence`
  helpers bind ordinary text, numeric, and selection controls to `UiState`
  record IDs while rejecting secure-field values and stale handles.
  The shared hello reference app adds a small typed list/detail catalog in
  `examples/hello/catalog.elisa` and persists its selected item with the form.
  Its `examples/hello/resource_demo.elisa` module exercises loading progress,
  completion, retryable failure, and recovery without taking resource authority
  away from the host.
- **Resources** ([src/widgets/ui_resources.elisa](src/widgets/ui_resources.elisa)) —
  a bounded, typed logical-resource state machine. The small public facade is
  backed by cohesive identity, query, demand/progress, transition, and metadata
  modules. Requests deduplicate by key, keep owner/generation lifetimes,
  separate network and decode progress, expose retry/cancel/dispose transitions,
  and raise resource/paint invalidation while hosts and SDKs retain authority
  over bytes, caching and decoding.
- **Resource presentation** ([src/widgets/ui_resource_presentation.elisa](src/widgets/ui_resource_presentation.elisa)) —
  maps resource lifecycle into explicit placeholder/loading/ready/fallback
  records with declared-or-intrinsic reserved geometry, independent progress,
  retry affordances, and kind-specific defaults. It keeps presentation policy
  in Elisa; hosts only resolve verified resources into renderer objects.
- **Optional feature views** ([src/widgets/ui_feature_view.elisa](src/widgets/ui_feature_view.elisa)) —
  a host-agnostic activation state machine for optional code components. The
  SDK/host remains authoritative for package identity, verification, component
  memories, permissions, and activation handles; Elisa owns only the typed
  loading/ready/error/cancelled state shown by the view. See
  [docs/ui-feature-views.md](docs/ui-feature-views.md).
- **Apps** implement `app_init` / `app_event(UiCore::Event)` /
  `app_text_input(sview)` / `app_text_editing(sview, i32, i32)` / `app_frame`, plus
  `app_widget_event(widget, event)` when using the widget layer. Physical keys
  and committed UTF-8 text are deliberately separate so layouts and IMEs are
  not reconstructed from key codes. These
  four are top-level by name; an app's own state and helpers belong in its
  own module, as [examples/hello/app.elisa](examples/hello/app.elisa) shows.

Backend selection is by include: each example has a `native_main.elisa` and a
`wapp_main.elisa` entry that include the same `app.elisa`.

See [docs/custom-appkit-canvas.md](docs/custom-appkit-canvas.md) for the
custom-painted AppKit API, application contract, controls and off-screen test
workflow. The flat widget layer also exposes a persistent `UiFlat::Theme` for
shared focus, selection, indicator and control-metric tokens; individual widget
surface and text colors remain independently configurable. Its text controls
include a secure-field variant whose value stays masked across painting,
accessibility and clipboard export.

The optional C boundary is demonstrated by the small
[examples/capi/c_host.c](examples/capi/c_host.c) program. It drives the Elisa
adapter through the versioned header and receives typed event, committed text,
and IME callbacks without seeing retained widget storage. The adjacent
[examples/capi/cpp_header_check.cc](examples/capi/cpp_header_check.cc) keeps
the same header C++17-compatible. `scripts/check_capi.sh` compiles both
examples and links the C host against the Elisa adapter; this path is optional
and does not add a dependency to native SDL, AppKit, Skia, or WasmBrowser apps.

wxWidgets serves as an architectural reference (widget hierarchy, sizers, event
routing) — studied, not ported.

## Build

The scripts use the synchronized `../wasm-sdk-compiler` checkout by default
(override with `ELISA_UI_STAGE1`):

```sh
scripts/build_native.sh   # -> build/hello_native (needs brew's sdl3 and sdl3_ttf)
scripts/build_appkit_canvas.sh # -> build/hello_appkit_canvas.app (macOS)
scripts/build_wapp.sh     # -> build/hello.wapp (+ build/hello.wasm)
scripts/check_wapp.sh      # inspect an existing package without recompiling
scripts/run_tests.sh      # builds and runs test/*_test.elisa
```

Headless interaction and frame tests can use the deterministic Elisa-side
[`UiHarness`](docs/ui-test-harness.md), which injects time and typed events
without opening a native surface.

The `.wapp` build needs `wasm-component-ld` (ships with Rust's `wasm32-wasip2`
target) and the `wasm-browser` CLI for the packing step; set `WASM_BROWSER_CLI`
or run `cargo build -p wb-cli` in the WasmBrowser checkout. It finds the WIT
world at `../WasmBrowser/wit/wasmbrowser.wit` (override with `ELISA_UI_WIT`).
The script stages the pinned Elisa SDK bindings under a stable `sdk/` source
root before compilation; override the SDK checkout with `ELISA_UI_WASM_SDK`.
The retained text and edit-history buffers need a 2 MiB initial linear heap;
`scripts/build_wapp.sh` passes that policy as `ELISA_WASM_INITIAL_PAGES` (default
`32`) and `ELISA_WASM_MAX_PAGES` (default `32768`) to stage1. The hello manifest
declares the corresponding `clipboard` capability.

Run native: `./build/hello_native`; headless check with
`SDL_VIDEODRIVER=dummy ELISA_UI_SMOKE_FRAMES=1 ./build/hello_native`. Inspect the
package with `wasm-browser inspect build/hello.wapp`.

Run the custom macOS renderer with `open build/hello_appkit_canvas.app`. It is
packaged and ad-hoc signed as a Retina-capable application with standard macOS
menus. Its custom-drawn labels and controls are mirrored into a semantic tree,
so VoiceOver sees roles, labels, help text, enabled/focused/selected state and
actionable controls rather than one opaque canvas. The same semantics also
drive native pointing-hand cursors and AppKit tooltips.

For a non-interrupting runtime check, run
`ELISA_UI_SMOKE_FRAMES=1 ./build/hello_appkit_canvas`. This constructs the real
AppKit view and renders one frame off-screen without showing or activating a
window; `scripts/check_appkit_canvas.sh` uses this mode automatically. Add
`ELISA_UI_SNAPSHOT=/absolute/path/frame.png` to save that frame for visual
regression inspection without foregrounding the application.

The native backend loads a font with SDL_ttf; set `ELISA_UI_FONT` to override
the default. Text still measures through the platform contract on both
backends, so layout agrees even though the rasterizers differ.
SDL supplies monotonic frame time and waits for either input or the earliest
animation deadline requested by the retained tree, keeping idle windows from
busy-spinning while preserving caret animation.
The current AppKit canvas calls libSystem, CoreGraphics, CoreText and ImageIO
directly from Elisa for its monotonic clock, path rendering, colors, shadows,
font metrics and off-screen PNG snapshots; Objective-C remains only where
Cocoa requires objects, delegates, protocols, and selectors. New custom
rendering work targets the Skia FFI described above; the native-controls path
continues to use AppKit directly.

### Elisascript ports (not yet runnable)

`build_native.elisascript` and `build_wapp.elisascript` are ports of the two
shell scripts to [Elisascript](../elisa-script), intended to replace them. They
are **unvalidated**: the Elisascript toolchain does not currently build against
the present Elisa compiler, so nothing has lowered or run them yet. The `.sh`
scripts remain the working path until then.
