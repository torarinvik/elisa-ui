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

The first slice covers clear, clipping, rounded rectangles, circles, triangles,
lines, UTF-8 text, and text metrics. The portable `FillRect` command keeps its
wire shape, while `UiPaint::rounded_rect_style()` supplies the shared Elisa
rounded-corner, hairline, and elevated-control shadow policy to both the Skia
and CoreGraphics custom painters; custom controls can request an explicit
radius through `UiSkia::fill_rounded_rect()`. The shadow FFI remains a single
geometry primitive, so target-specific blur/GPU behavior stays inside Skia.
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

The same rule applies to host-provided typefaces: `draw_ready_text` accepts a
borrowed `SkTypeface*` only for a ready font generation, while bounded text
geometry and resource lifetime remain Elisa/SDK responsibilities. The matching
`measure_ready_text_width`, `ready_font_ascent`, and `ready_font_line_height`
queries use that same borrowed typeface, avoiding a default-font metric mismatch.

The checkout does not currently pin or vendor a Skia SDK. Build the C++ shim
only in a target that supplies Skia headers and libraries, then pass its
`SkCanvas*` through the opaque FFI handle. The Elisa module itself compiles
without Skia installed, so layout, command generation, and all existing
headless tests remain independent of the renderer choice.
