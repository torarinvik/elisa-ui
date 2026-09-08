# Skia custom rendering

The native-control backend remains AppKit, while the custom-painted backend is
Skia. The split is intentional. The current AppKit canvas still has a
CoreGraphics fallback for off-screen and legacy hosts until a pinned Skia
surface is supplied; that fallback is not the native-control path:

- AppKit owns native controls, text services, accessibility protocol objects,
  windows, and event delivery in the native profile.
- Elisa owns retained widgets, layout, semantic nodes, clipping decisions, and
  the portable `UiCore::Command` batch in both profiles.
- Skia owns custom pixels only. `src/platform/skia/ui_skia.elisa` is the Elisa
  painter specialization; `skia_canvas_shim.cpp` is the narrow C ABI that
  accepts an opaque borrowed `SkCanvas*` and exposes primitive operations.

The real renderer check is a required gate. `scripts/check_skia.sh` validates
the lockfile revision, compiles the narrow bridge, and runs the headless CPU
raster fixture when `SKIA_ROOT` and its pinned `libskia.a` are present. The
off-screen and showcase scripts repeat the same clean-checkout verification
through `scripts/verify_skia_pin.sh`, so invoking either fixture directly
cannot silently use a different or dirty Skia source tree;
`scripts/run_tests.sh` invokes that gate by default. Set
`ELISA_UI_REQUIRE_REAL_SKIA=0` only for an explicitly incomplete compiler-only
edit loop on a machine without the checkout; that mode is not a renderer pass.
`scripts/build_skia.sh` accepts either a normal checkout or a linked Git
worktree, rejects tracked and untracked edits before fetching, and writes an
archive provenance manifest after the build. The standalone AppKit/Skia
builder uses that same manifest check, and the same pin and archive-hash
verifier runs before every real fixture, so a copied or stale `libskia.a` is
rejected instead of being mistaken for renderer evidence.
After the primitive fixture, the gate runs `scripts/check_showcase_skia.sh`.
That headless host includes the shipped `examples/hello/app.elisa`, drives its
public focus, text-editing, state, and resource-generation callbacks, and
checks the final retained layout for real rasterized custom artwork. The
showcase check also reports repeated frame timing, making renderer milestones
something an application can reproduce rather than a collection of helper-only
combinations.

The FFI deliberately does not expose `SkPaint`, `SkFont`, `SkPath`, or any
other C++ object to Elisa. A host can call the one-shot exported
`elisa_skia_render_frame(canvas)` boundary, which attaches one borrowed canvas,
replays the retained batch, and detaches it before returning. Elisa owns
command replay and normalizes direct painter geometry before any value crosses
the FFI. Hosts that need explicit phases may use `UiSkia::attach()`,
`UiSkia::render()`, and `UiSkia::detach()` directly; scaled hosts can use
`UiSkia::attach_scaled()` or the exported
`elisa_skia_render_frame_scaled(canvas, scale)` boundary. The scale transform
is wrapped in a balanced frame save/restore, so surface recreation cannot
accumulate transforms. Font metrics are
independent of the borrowed canvas, so layout can query Skia before surface
attachment. That makes surface recreation and headless rendering ordinary
lifecycle transitions instead of retained native pointer state.

The AppKit compositor forwards logical and backing-pixel dimensions to the
Elisa replay callback; `UiCore::backing_scale()` selects the finite
aspect-preserving scale there. The C++ host only rounds/limits pixel extents
for its temporary allocation and no longer embeds a rendering-scale policy.
The replay status is also split at the Elisa boundary: zero means rejection
before `app_frame`, while a negative result means the frame was already
consumed and must not be replayed by the CoreGraphics fallback. This keeps
lifecycle interruptions and late presentation failures safe without moving
application state into the native shim.
These sentinels are published as `ELISA_APPKIT_SKIA_PRESENT_REJECTED` and
`ELISA_APPKIT_SKIA_PRESENT_CONSUMED_NO_PRESENTATION` in
`include/elisa_appkit_skia.h`, so host callers do not duplicate numeric status
policy. The optional AppKit host also checks the packed `ELISA_SKIA_ABI_VERSION`
major before creating a surface or passing borrowed handles to Elisa; a
mismatch returns the same pre-frame rejection and remains fallback-safe.
When presenting the completed raster, it draws into the logical view bounds so
AppKit's device transform performs the one logical-to-backing conversion; this
keeps Retina and other non-1x contexts from scaling the image twice.

When a host has a resolved system or bundled typeface, the one-shot
`elisa_skia_render_frame_with_font_status(canvas, font)` boundary supplies it
for the current replay only. The `SkTypeface*` remains host-owned; Elisa uses
the handle to route retained text through Skia and releases no native object.
Generation-bound `draw_ready_text` remains the preferred form for long-lived
font resources.

The public header also exposes `elisa_skia_abi_version()` and the packed
`ELISA_SKIA_ABI_VERSION` constant. Hosts can reject a major mismatch before
passing any opaque canvas, image, or typeface handle across the boundary.

Canvas-independent Skia text metrics live in the focused
`ui_skia_text.elisa` extension. The facade keeps only replay-time text drawing,
while measurement, ascent, and line-height queries share one bounded FFI
authority that layout can call before a surface exists. Widget painting wraps
the line-height and bounded text-width queries in the frame-local Elisa-owned
`UiTextMetrics` cache, so repeated controls and text ranges reuse backend
results without retaining a font or Skia object across frames; paint and
retained-tree resets are the explicit invalidation boundaries for font and
scale changes. Width keys are copied into a small table and oversized text
bypasses it, keeping cache memory and comparison work bounded.
The custom Skia adapter adds a second bounded byte-keyed width cache for
grapheme layout, keyed by the active borrowed font handle and normalized size.
Repeated wrapping, hit testing, selection, and caret queries therefore reuse
the same metric without another FFI call; scale/binding resets explicitly clear
the cache, and clusters larger than its copy budget bypass it.

Direct geometry calls and replayed commands share the private
`ui_skia_geometry.elisa` policy. Coordinates and extents are finite and capped,
empty rectangles/circles are rejected, circle radii are clamped so the full
disk stays inside the shared envelope (including half the stroke width for
stroked circles), and corner radii are clamped to half the shortest box edge
before reaching Skia. The C++ bridge therefore remains a primitive adapter
rather than a second, drifting geometry policy.

Custom controls can use `UiSkia::push_transform()` and
`UiSkia::pop_transform()` for translated/scaled drawing scopes. The
`ui_skia_transform.elisa` extension owns finite offset/positive-scale
normalization, plus `push_rotation()` for finite degree-based rotation, and a
shared save-depth ledger; detach and surface loss restore any forgotten scopes
before the borrowed canvas is released.

Immediate custom drawing can also call `stroke_rounded_rect`, `fill_circle`,
`stroke_circle`, `fill_triangle`, and `stroke_line` from
`ui_skia_primitives.elisa`. These helpers apply the same finite-geometry,
alpha, and stroke-width policy as retained replay, then forward only primitive
arguments through the Skia FFI; custom controls never construct or retain Skia
C++ objects.

AppKit creates its temporary SkCanvas after the application frame callback.
Skia-specific controls that need richer primitives during that callback can use
the explicit `UiSkia::begin_deferred_frame()` / `end_deferred_frame()` scope
and the `defer_*` helpers in `ui_skia_deferred.elisa`. Elisa copies bounded
command values (including text) into a fixed side-band queue and records the
retained command count at each enqueue. Replay consumes one ordered stream: it
replays retained commands up to the next anchor, then the deferred record, and
continues until both streams are exhausted. Deferred painting is therefore not
overlay-only; a custom control can appear before, between, or after retained
widgets. Deferred clip/transform scopes also remain active across intervening
retained commands, so their ordering follows the same frame sequence.
Queue overflow reports through the same `CommandOverflow` status. Surface loss
cancels the queue. The hosted six-command protocol remains unchanged, and no
Skia object or native save scope can outlive the frame.

The required `test/showcase_skia_test.elisa` fixture exercises this contract
through the shipped `examples/hello/app.elisa`: it resolves the retained
content-card handle, queues an orange deferred badge, emits an overlapping
retained divider, and queues a magenta deferred circle. It drives the public
editable-field and validation callbacks through an invalid-to-valid edit before
the frame is replayed. It also binds a
deterministic host-decoded image to the app's logical resource, queues the old
generation, rotates it through the public retry API, and queues the replacement
generation before replay. The real Skia host checks the three overlap pixels,
the skipped stale-generation placeholder, the rendered replacement image, ink
inside the edited text field's live retained bounds, and the final validation
status label; an overlay-only
renderer, a renderer that ignores generation identity, or a renderer that
never paints the edited text fails the application-level gate.

The AppKit/Skia compositor fixture repeats its CoreGraphics presentation and
compares the logical pixel digest, while reporting the elapsed presentation
time. This catches a borrowed-surface replay that leaks state even when the
standalone CPU-raster showcase remains stable.

`UiSkia::fill_linear_gradient()` adds a bounded two-stop horizontal or vertical
surface fill. Elisa owns the colors, orientation, transparency, and rectangle
validation; the C++ boundary only creates the Skia shader and draws the rect.

For custom geometry, `UiSkia::empty_polygon()`, `polygon_add()`,
`fill_convex_polygon()`, and `stroke_convex_polygon()` keep up to 32
Elisa-owned points, fan-triangulate fills, and close outlines through the
existing bounded line primitive. This provides a bounded path-like escape
hatch without exposing `SkPath` or allocating native path state; callers must
supply a convex, consistently wound polygon.

Both immediate helpers and retained replay cull fully transparent fills,
strokes, and text in Elisa before crossing the FFI; `Clear` remains explicit
because clearing to transparent is observable surface state.

Clip and transform saves share a bounded Elisa-owned kind stack. A mismatched
typed pop is rejected without restoring the wrong native state, and detach
still unwinds any remaining scopes before releasing the borrowed canvas.

Immediate custom drawing can also use `UiSkia::push_clip()` and
`UiSkia::pop_clip()` from `ui_skia_clip.elisa`. Empty clips are rejected before
Skia, and clip saves share the same ledger as transforms and the attachment
frame, so retained replay and custom scopes cannot drift in their restoration
rules. Retained replay intentionally submits zero-area intersections to Skia so
an empty nested viewport suppresses its commands; only the immediate helper's
caller-facing input contract rejects them.

When a custom control needs a shaped viewport, `UiSkia::push_rounded_clip()`
uses the same typed pop and detach guarantees while clamping the radius to the
box in Elisa. The bridge only receives the bounded rectangle and radius and
clips with Skia's `clipRRect`; it does not choose a visual default or retain a
native path object.

`UiSkia::fill_rounded_linear_gradient()` composes that scope with the existing
two-stop gradient helper. It is intentionally an Elisa-only convenience: the
clip is opened, the validated gradient is issued, and the clip is closed in one
bounded call, so custom controls cannot leak a native save or shader lifetime.

Shadow colors are likewise framework values. `draw_shadow_rounded_rect()` keeps
the legacy black shorthand, while `draw_shadow_rounded_rect_with_color()` sends
an explicit Elisa `Color` through the additive color-aware bridge; the older
native symbol remains only as a compatibility wrapper for hosts built against
the previous ABI.

The deferred API has matching `defer_fill_rounded_linear_gradient()` and
`defer_shadow_rounded_rect()` helpers. Rounded gradients replay through the
same temporary clip scope as immediate drawing, while shadows carry explicit
offset, blur, radius, and color values in the Elisa queue; the color-aware
`defer_shadow_rounded_rect_with_color()` form keeps custom effects consistent
with immediate drawing. Neither operation adds a native object or an implicit
style default.

Convex custom shapes can use `defer_fill_convex_polygon()` and
`defer_stroke_convex_polygon()`. Elisa expands each bounded polygon into the
existing triangle/line commands only after reserving the complete queue budget,
so exhaustion rejects the whole shape instead of presenting a partial fan or
outline.

Deferred scopes (`defer_push_clip()`, `defer_push_rounded_clip()`,
`defer_push_transform()`, `defer_push_rotation()`, and their typed pops) keep an
Elisa-side LIFO ledger. Replay reuses the immediate save/clip/transform helpers,
and mismatched or over-budget pops are rejected before they can restore the
wrong native state. Scope-depth exhaustion marks the frame incomplete through
the same `CommandOverflow` status as command-capacity exhaustion.

Deferred image helpers (`defer_image_fitted*()` and
`defer_image_fitted_rounded*()`) carry source dimensions, fit mode, sampling,
and radius in the Elisa queue. Replay calls the immediate fitted-image helpers,
so contain/cover/scale-down placement and temporary clip scopes stay identical
between controls that draw during the callback and controls that draw after a
SkCanvas is attached. Only the opaque image handle crosses the boundary.
Immediate and deferred `draw_image_source*()` / `defer_image_source*()` helpers
add an explicit pixel-space source rectangle for sprite sheets, thumbnails, and
pan/zoom views while keeping a separate logical destination rectangle. Elisa
normalizes both rectangles and the sampling policy; the native bridge only
forwards the two sanitized rectangles to `SkCanvas::drawImageRect`. The
generation-safe `draw_bound_image_source*()` and
`defer_bound_image_source*()` variants retain only the logical resource token,
so a disposed or recycled image cannot be used by a later crop.
When verified `UiResources::set_intrinsic_size()` metadata is available, these
resource-bound crop forms also clamp the source rectangle to the decoded image
extent in Elisa; resources without metadata retain the shared finite-envelope
policy.
The `*_source_rounded*()` forms compose the same crop with an Elisa-owned
rounded clip for polished thumbnails and avatars; immediate and deferred
variants share the typed save/restore ledger.

Generation-bound deferred image helpers (`defer_bound_image_fitted*()` and
their intrinsic/rounded variants) store a logical resource slot and generation,
not a native image pointer. Replay reconstructs that handle and resolves the
current Elisa binding only while the resource is ready; disposed or recycled
generations are skipped safely. Binding-index repair is bounded and generation
aware, so resource teardown and surface recreation cannot redirect a queued
command to a different image.
The direct `defer_bound_image*()` forms use the same identity contract when a
control already has its final destination rectangle and does not need fitting;
sampling remains an explicit Elisa enum rather than a native filter object.

`UiSkia::snapshot()` is a read-only diagnostic record for attachment/generation,
save depth, clip/transform depth, active image/font bindings, and deferred
queue activity/count/overflow/scope depth;
`UiSkia::is_balanced()` provides the corresponding invariant check. These
diagnostics expose lifecycle facts without handing hosts mutable state or native
object pointers.

`UiSkia::surface_lost()` explicitly invalidates the borrowed canvas without
discarding retained commands or logical resources. `surface_generation()`
advances on loss and every new attachment, giving a host a cheap stale-surface
token while the Elisa widget tree survives device/surface recreation. Passing a
zero canvas to `attach()`/`attach_scaled()` follows the same loss path and
advances the token instead of silently reusing the prior generation.
Surface loss also clears all borrowed image/typeface bindings; a recreated
surface must explicitly bind fresh renderer objects while logical resources
remain available to the view.
Changing the logical-to-physical scale follows the same rule: the active scale
is tracked in Elisa diagnostics and scale-sensitive borrowed bindings are
cleared before the replacement frame is attached.

Hosts that need an explicit completeness signal can call
`UiSkia::render_checked()`: it replays the bounded batch but returns `false`
when `UiCore` dropped commands at its fixed capacity, making incomplete frames
observable without allowing an unbounded render allocation.
`UiSkia::render_status()` exposes the typed result behind that compatibility
boolean: `SkippedNoSurface`, `Complete`, or `CommandOverflow`.

The checked-in source pin is `third_party/skia.lock`: Skia `chrome/m150` at
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`, with a deterministic macOS arm64
CPU-raster GN configuration. The SDK and generated archive are kept out of the
repository. With depot_tools installed, the lockfile-driven
`SKIA_ROOT=/path/to/skia SKIA_OUT=/path/to/skia/out/elisa bash
scripts/build_skia.sh` command fetches the exact revision, syncs DEPS, runs the
pinned GN arguments, and builds `libskia.a`; then
`SKIA_ROOT=/path/to/skia SKIA_OUT=/path/to/skia/out/elisa bash
scripts/check_skia.sh` compiles the real bridge, links the production shim with
the Elisa fixture, renders a real off-screen `SkSurface`, checks representative
shape and glyph pixels, and saves a PNG; it never orders an AppKit window onscreen.
`src/platform/appkit/appkit_skia_host.cpp` provides
the optional AppKit compositor: when linked, `drawRect` hands its borrowed
CoreGraphics context to this bridge, which presents the temporary Skia surface;
the ordinary AppKit build still uses its CoreGraphics fallback.

The first slice covers clear, rectangular and rounded clipping, rounded rectangles, two-stop gradients,
circles, triangles, lines, UTF-8 text, and text metrics. The portable `FillRect` command keeps its
wire shape. Generic fills use the shared rounded-corner and subtle hairline
policy; an explicit `UiCore::fill_elevated()` call records an Elisa-owned
side-band style bit, and replay passes that bit to
`UiPaint::rounded_rect_style()` so only intentional control surfaces receive
the stronger elevation shadow. The same style policy is consumed by both the
Skia and CoreGraphics custom painters; custom controls can request an explicit
radius through `UiSkia::fill_rounded_rect()`. `UiPaint::RoundedRectStyle` owns the
shadow offset, blur, hairline width, and alpha values shared by both custom
painters; the private `ui_skia_style.elisa` extension only translates that
record into explicit FFI arguments, leaving the C++ bridge to construct the
target-specific `SkPaint` effect. Non-positive stroke widths
are rejected by the bridge instead of receiving an undocumented fallback.
Rounded radii are constrained by `ui_skia_geometry.elisa` before crossing the
ABI; the bridge forwards those values directly to `SkRRect` without a second
appearance default and rejects malformed negative/NaN direct calls.
Custom controls that need immediate text use `UiSkia::draw_text_run()`, which
shares the retained path's bounded coordinates, UTF-8 prefix, and 1pt minimum
font-size policy before crossing the ABI. Wrapped blocks use the same measured
Skia authority through `UiSkia::draw_text_block_positioned()`, with explicit
horizontal and vertical alignment and an Elisa-owned clip scope. GPU surface
creation and an AppKit `MTKView`/`SkSurface` host are intentionally separate
follow-ups; they must be chosen with the target's pinned Skia build rather than
smuggled into the Elisa ABI.
`draw_text_block_interactive()` composes selection, glyphs, and caret painting
in one measured pass, preserving selection-before-text/caret-after-text order
and sharing one clip scope. Blink visibility remains widget state; the compound
operation only consumes the caller's explicit `TextInteraction` range/colors.
Generation-bound typefaces have matching primary and fallback forms, so this
single-pass path does not require a control to expose or duplicate font scopes.

Ready generation-bound typefaces can use `layout_bound_text()` and
`draw_bound_text_block()` (or their fallback forms), which scope the selected
borrowed font for the complete measure-and-draw operation.

Image presentation follows the same boundary: the host decodes and owns an
opaque `SkImage*`, while Elisa validates the destination rectangle and alpha
before issuing a borrowed `drawImageRect` call. `UiSkia` never retains or frees
the image handle, so resource lifetime remains with the host/SDK. The
`draw_ready_image` helper additionally requires a live `UiResources` generation
in the `Ready` state before a host image can be painted.
The default `draw_image()` path uses linear filtering; custom controls can call
`draw_image_with_sampling()` with the typed Elisa `ImageSampling.Nearest` policy
for crisp pixel art. Invalid enum values normalize back to linear before the
sampling code reaches Skia.
For non-stretching layouts, `draw_image_fitted()` and its resource-bound
variants apply the Elisa `ImageFit.Contain`, `ImageFit.Cover`, or
`ImageFit.ScaleDown` policy using verified source dimensions. Contain centers
the complete image; Cover centers the crop and opens a temporary destination
clip so pixels cannot bleed outside the caller's box; ScaleDown preserves the
intrinsic size of an asset that already fits while still shrinking an oversized
asset. The native bridge still receives only the final rectangle, sampling
ordinal, and borrowed image handle.
When a logical image has `UiResources::set_intrinsic_size()` metadata,
`draw_bound_image_fitted_intrinsic()` derives source dimensions from that
generation-scoped record, keeping decoded-image facts out of ordinary widget
state.
`draw_image_fitted_rounded()` and the intrinsic bound variants add a typed
rounded clip around the fitted destination, making avatar/card presentation a
composition of Elisa scopes rather than a new native image primitive.
The ready and generation-bound image helpers expose matching
`*_with_sampling()` forms, so filtering survives the resource-binding path.
Hosts can use `bind_image`/`draw_bound_image` to associate that pointer with an
exact `(slot,generation)` token; recycled resource generations cannot reuse an
old image binding. Elisa stores the opaque value only and exposes explicit
unbind/clear operations before host disposal. `prune_bindings()` also removes
entries whose logical resource is no longer `Ready`; draw, bind, and metric
queries invoke it automatically, including fitted-image calls that reject a
stale generation before drawing, while `clear_resource_bindings()` provides one
teardown call for a resource that may have both image and font bindings.
Per-resource image and font lookups use Elisa-owned reverse indexes keyed by
the resource slot, then validate the generation before returning the borrowed
handle. This keeps hot draw/metric queries independent of the binding-table
length while the bounded prune sweep still cleans up stale entries and clears
their index slots.

The same rule applies to host-provided typefaces: `draw_ready_text` accepts a
borrowed `SkTypeface*` only for a ready font generation, while bounded text
geometry and resource lifetime remain Elisa/SDK responsibilities. The matching
`measure_ready_text_width`, `ready_font_ascent`, and `ready_font_line_height`
queries use that same borrowed typeface, avoiding a default-font metric mismatch.
`bind_font`/`draw_bound_text` provide the stricter generation-keyed form for
hosts that keep decoded typefaces in a resource cache; bound metric queries use
the same association. `*_with_fallback` forms keep primary/fallback selection
in Elisa and apply the same choice to drawing and metrics; per-glyph shaping
fallback remains the host's typeface/shaper responsibility. `ui_skia_text.elisa`
applies a bounded 1pt minimum font size to every framework draw and metric
query; direct native calls with a non-positive size are rejected by the bridge
instead of selecting an implicit fallback.

The checkout pins the Skia source/build contract but does not vendor the SDK
or generated archive. Build the C++ shim only in a target that supplies Skia
headers and libraries, then pass its
`SkCanvas*` through the opaque FFI handle. The Elisa module itself compiles
without Skia installed, so layout, command generation, and all existing
headless tests remain independent of the renderer choice.

Custom surfaces may use `UiSkia::fill_themed_surface` with an explicit
`UiTheme::Metrics` record. Radius clamping and shadow/outline policy remain in
Elisa before the narrow Skia primitive calls.

Native hosts can include [`include/elisa_skia.h`](../include/elisa_skia.h) for
the exact C declarations. It documents borrowed-handle ownership and keeps the
production bridge and headless recorder on the same ABI without exposing Skia
objects to Elisa.
