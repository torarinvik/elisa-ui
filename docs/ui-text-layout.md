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
