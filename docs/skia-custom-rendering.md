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
authority that layout can call before a surface exists.

Direct geometry calls and replayed commands share the private
`ui_skia_geometry.elisa` policy. Coordinates and extents are finite and capped,
empty rectangles/circles are rejected, and corner radii are clamped to half the
shortest box edge before reaching Skia. The C++ bridge therefore remains a
primitive adapter rather than a second, drifting geometry policy.

Custom controls can use `UiSkia::push_transform()` and
`UiSkia::pop_transform()` for translated/scaled drawing scopes. The
`ui_skia_transform.elisa` extension owns finite offset/positive-scale
normalization, plus `push_rotation()` for finite degree-based rotation, and a
shared save-depth ledger; detach and surface loss restore any forgotten scopes
before the borrowed canvas is released.

Immediate custom drawing can also use `UiSkia::push_clip()` and
`UiSkia::pop_clip()` from `ui_skia_clip.elisa`. Empty clips are rejected before
Skia, and clip saves share the same ledger as transforms and the attachment
frame, so retained replay and custom scopes cannot drift in their restoration
rules. Retained replay intentionally submits zero-area intersections to Skia so
an empty nested viewport suppresses its commands; only the immediate helper's
caller-facing input contract rejects them.

`UiSkia::snapshot()` is a read-only diagnostic record for attachment/generation,
save depth, clip/transform depth, and active image/font bindings;
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

Hosts that need an explicit completeness signal can call
`UiSkia::render_checked()`: it replays the bounded batch but returns `false`
when `UiCore` dropped commands at its fixed capacity, making incomplete frames
observable without allowing an unbounded render allocation.
`UiSkia::render_status()` exposes the typed result behind that compatibility
boolean: `SkippedNoSurface`, `Complete`, or `CommandOverflow`.

The checked-in source pin is `third_party/skia.lock`: Skia `chrome/m150` at
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`, with a deterministic macOS arm64
CPU-raster GN configuration. The SDK and generated archive are kept out of the
repository, but a host can fetch Skia's DEPS, build `libskia.a`, and run
`SKIA_ROOT=/path/to/skia SKIA_OUT=/path/to/skia/out/elisa bash
scripts/check_skia.sh`. That command compiles the real bridge, links the
production shim with the Elisa fixture, renders a real off-screen `SkSurface`,
checks representative shape and glyph pixels, and saves a PNG; it never orders
an AppKit window onscreen. `src/platform/appkit/appkit_skia_host.cpp` provides
the optional AppKit compositor: when linked, `drawRect` hands its borrowed
CoreGraphics context to this bridge, which presents the temporary Skia surface;
the ordinary AppKit build still uses its CoreGraphics fallback.

The first slice covers clear, clipping, rounded rectangles, circles, triangles,
lines, UTF-8 text, and text metrics. The portable `FillRect` command keeps its
wire shape. Generic fills remain plain; an explicit `UiCore::fill_elevated()`
call records an Elisa-owned side-band style bit, and replay passes that bit to
`UiPaint::rounded_rect_style()` so only intentional control surfaces receive
the elevated shadow. The same style policy is consumed by both the Skia and
CoreGraphics custom painters; custom controls can request an explicit radius
through `UiSkia::fill_rounded_rect()`. Skia's private
`ui_skia_style.elisa` extension supplies the shadow offset, blur, and 1px
hairline constants through explicit FFI arguments, leaving the C++ bridge to
construct only the target-specific `SkPaint` effect. Non-positive stroke widths
are rejected by the bridge instead of receiving an undocumented fallback.
Rounded radii are constrained by `ui_skia_geometry.elisa` before crossing the
ABI; the bridge forwards those values directly to `SkRRect` without a second
appearance default and rejects malformed negative/NaN direct calls.
Custom controls that need immediate text use `UiSkia::draw_text_run()`, which
shares the retained path's bounded coordinates, UTF-8 prefix, and 1pt minimum
font-size policy before crossing the ABI.
Font fallback, image resources, GPU surface
creation, and an AppKit `MTKView`/`SkSurface` host are intentionally separate
follow-ups; they must be chosen with the target's pinned Skia build rather than
smuggled into the Elisa ABI.

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
The ready and generation-bound image helpers expose matching
`*_with_sampling()` forms, so filtering survives the resource-binding path.
Hosts can use `bind_image`/`draw_bound_image` to associate that pointer with an
exact `(slot,generation)` token; recycled resource generations cannot reuse an
old image binding. Elisa stores the opaque value only and exposes explicit
unbind/clear operations before host disposal. `prune_bindings()` also removes
entries whose logical resource is no longer `Ready`; draw, bind, and metric
queries invoke it automatically, while `clear_resource_bindings()` provides one
teardown call for a resource that may have both image and font bindings.

The same rule applies to host-provided typefaces: `draw_ready_text` accepts a
borrowed `SkTypeface*` only for a ready font generation, while bounded text
geometry and resource lifetime remain Elisa/SDK responsibilities. The matching
`measure_ready_text_width`, `ready_font_ascent`, and `ready_font_line_height`
queries use that same borrowed typeface, avoiding a default-font metric mismatch.
`bind_font`/`draw_bound_text` provide the stricter generation-keyed form for
hosts that keep decoded typefaces in a resource cache; bound metric queries use
the same association. `ui_skia_text.elisa` applies a bounded 1pt minimum font
size to every framework draw and metric query; direct native calls with a
non-positive size are rejected by the bridge instead of selecting an implicit
fallback.

The checkout pins the Skia source/build contract but does not vendor the SDK
or generated archive. Build the C++ shim only in a target that supplies Skia
headers and libraries, then pass its
`SkCanvas*` through the opaque FFI handle. The Elisa module itself compiles
without Skia installed, so layout, command generation, and all existing
headless tests remain independent of the renderer choice.

Native hosts can include [`include/elisa_skia.h`](../include/elisa_skia.h) for
the exact C declarations. It documents borrowed-handle ownership and keeps the
production bridge and headless recorder on the same ABI without exposing Skia
objects to Elisa.
