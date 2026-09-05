# Text line-break policy

`UiTextLayout` keeps line-break decisions in Elisa while leaving shaping,
font fallback, and pixel measurement to the selected renderer. It advances
valid and malformed UTF-8 safely by scalar, honors LF/CRLF newlines, prefers
whitespace/hyphen/slash break points, and hard-breaks an unbreakable word at a
deterministic scalar-column boundary.

The planner stores at most `MAX_LINES` ranges and reports overflow instead of
allocating without bound. `line_view` returns a borrowed slice of the original
text, so no text copy or backend-specific string object crosses the policy
layer. The current budget is scalar columns; a future measured-width planner
can reuse the same ranges and replacement rules with CoreText, SDL_ttf, or a
host font authority.
