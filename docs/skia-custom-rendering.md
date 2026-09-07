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
rules.

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

The first slice covers clear, clipping, rounded rectangles, circles, triangles,
lines, UTF-8 text, and text metrics. The portable `FillRect` command keeps its
wire shape, while `UiPaint::rounded_rect_style()` supplies the shared Elisa
rounded-corner, hairline, and elevated-control shadow policy to both the Skia
and CoreGraphics custom painters; custom controls can request an explicit
radius through `UiSkia::fill_rounded_rect()`. Skia's private
`ui_skia_style.elisa` extension supplies the shadow offset, blur, and 1px
hairline constants through explicit FFI arguments, leaving the C++ bridge to
construct only the target-specific `SkPaint` effect. Non-positive stroke widths
are rejected by the bridge instead of receiving an undocumented fallback.
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

The checkout does not currently pin or vendor a Skia SDK. Build the C++ shim
only in a target that supplies Skia headers and libraries, then pass its
`SkCanvas*` through the opaque FFI handle. The Elisa module itself compiles
without Skia installed, so layout, command generation, and all existing
headless tests remain independent of the renderer choice.

Native hosts can include [`include/elisa_skia.h`](../include/elisa_skia.h) for
the exact C declarations. It documents borrowed-handle ownership and keeps the
production bridge and headless recorder on the same ABI without exposing Skia
objects to Elisa.
