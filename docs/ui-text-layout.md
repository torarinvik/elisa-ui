# Text line-break policy

`UiTextLayout` keeps line-break decisions in Elisa while leaving shaping,
font fallback, and pixel measurement to the selected renderer. It advances
valid and malformed UTF-8 safely by scalar, honors LF/CRLF newlines, prefers
whitespace/hyphen/slash break points, and hard-breaks an unbreakable word at a
deterministic scalar-column boundary.

The planner stores at most `MAX_LINES` ranges and reports overflow instead of
allocating without bound. `line_view` returns a borrowed slice of the original
text, so no text copy or backend-specific string object crosses the policy
layer. `UiTextLayout` remains the allocation-free scalar-column planner used by
portable wire paths.

`UiTextMeasureLayout` is the measured-width companion for native and custom
painters. Its core accepts a `fn(sview, f32) -> f32` width provider, so each
backend can supply its real font authority. The default facade uses
`UiTextMetrics`; `UiSkia::layout_text` supplies Skia's own metric query and
uses the active borrowed frame typeface when one is present. The planner walks
the same grapheme boundaries and stores pixel-width ranges without copying the
source text. It prefers whitespace-run breaks, honors LF/CRLF, normalizes
hostile geometry, prefers whitespace and punctuation soft breaks while keeping
hyphens/slashes on the preceding line, and emits a single oversized grapheme so
malformed or unusually large glyphs cannot stall the planner. The metric cache and font
fallback policy therefore stay with the renderer while line ownership remains
in Elisa.

For immediate custom painting, `UiSkia::draw_text_block` consumes the same
layout and clips each line to its destination rectangle. The positioned variant
adds explicit start/center/end and top/center/bottom placement without moving
baseline policy into a host. Both return the layout record even when the
surface, color, or clip is unavailable, making overflow and line counts
observable without coupling application state to a native canvas. Lines that
fall wholly outside the destination are retained in the layout record but are
culled before the Skia FFI call.

When a logical `UiResources::ResourceHandle` is bound to a ready SkTypeface,
`UiSkia::layout_bound_text` and `UiSkia::draw_bound_text_block` scope that
generation for the whole operation. Their fallback forms choose the first
ready, bound generation and otherwise return an empty layout without crossing
the native boundary.

`UiSkia::hit_test_text_line()` maps a local pixel coordinate to the nearest
UTF-8 byte offset on a measured line. It reuses the active Skia width authority
and advances only grapheme clusters, so combining marks and multi-codepoint
emoji remain indivisible for caret and selection callers.
The backend-neutral `UiTextMeasureLayout::hit_test()` facade provides the same
contract through the active platform metric hook for non-Skia painters.
`UiTextMeasureLayout::caret_x()` and `UiSkia::caret_x_text_line()` perform the
inverse mapping for a source offset, flooring offsets inside a grapheme to its
leading edge before summing measured cluster widths.

`UiTextMeasureLayout::selection()` intersects a byte range with one measured
line and returns grapheme-normalized start/end offsets plus local x/width
geometry. `UiSkia::text_selection_rect()` adds the selected block's alignment
and font metrics, clips the rectangle to its destination, and
`UiSkia::fill_text_selection()` paints every non-empty line fragment inside a
short-lived clip scope. Call the fill helper before the corresponding text
block so the selection remains behind glyphs; the host supplies no selection
state or geometry policy.

`UiTextMetrics::reset()` is the paint-boundary invalidation hook. Backends must
also call `UiTextMetrics::set_context(font_generation, scale_generation)` when
the active font set or display scale changes; a new generation invalidates both
line-height and width caches.
`UiTextMetrics::snapshot()` exposes the active generations and bounded query/miss
counters for inspector and performance diagnostics.

`UiSkia::text_caret_rect()` and `UiSkia::draw_text_caret()` use the same
positioned line metrics for a grapheme-safe caret. Blink timing and visibility
remain application/widget state, while the helper bounds the caret to the
destination and paints it through the existing Elisa rounded-rectangle path.
`UiSkia::fill_bound_text_selection()` and `UiSkia::draw_bound_text_caret()`
scope a ready generation-bound typeface for those operations, while their
`with_fallback` variants choose the first ready bound generation. All return an
empty layout for loading, failed, cancelled, or stale resources just like the
bound text-block helpers.
