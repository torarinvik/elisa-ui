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
`UiTextMetrics`; `UiSkia::layout_text` supplies Skia's own metric query. The
planner walks the same grapheme boundaries and stores pixel-width ranges without
copying the source text. It prefers whitespace-run breaks, honors LF/CRLF,
normalizes hostile geometry, and emits a single oversized grapheme so malformed
or unusually large glyphs cannot stall the planner. The metric cache and font
fallback policy therefore stay with the renderer while line ownership remains
in Elisa.
