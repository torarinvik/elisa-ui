# Localization and RTL policy

`UiLocalization` keeps layout-affecting locale decisions in Elisa. It detects
common RTL language tags (`ar`, `fa`, `he`, `ur`, `ps`, `dv`, and `yi`), maps
logical start/end to the existing cross-axis alignment enum, and mirrors an
already-resolved item origin without allowing negative geometry.

The active locale is also retained in a bounded Elisa-owned buffer. `set_locale`
canonicalizes ASCII case and underscore separators, returns whether the value
changed, and exposes a monotonic `revision` plus a `snapshot` for inspectors or
adapters. Repeating the same canonical tag is a no-op; a real change invalidates
layout, paint, and semantics together. Oversized tags are copied as a bounded
prefix and reported as `truncated` rather than reaching native code unchecked.

`text_direction` resolves a paragraph base direction from the first strong
Unicode scalar, using the supplied locale direction for empty or neutral-only
text. It recognizes the major RTL scripts and common LTR script ranges while
leaving bidi reordering and glyph shaping to the renderer.

`plural` returns a typed category for the common English/French/Arabic,
Russian/Ukrainian, and Polish rules, with a deterministic one/other fallback
for unknown languages. Message catalogs remain application-owned; they consume
the category instead of making each backend parse locale strings independently.

Claim dynamic item identity through `UiIdentity` before rebuilding a localized
list so RTL/retranslation does not transfer focus or edit state by position.

## What the painter mirrors, and what it does not yet

A choice control's **marker and its label** follow the reader's direction: in a
right-to-left locale the box or ring sits on the trailing side and the caption
runs to the other side of it. The fitted left-to-right centre is *reflected*
rather than recomputed, which keeps the marker inside its control for free —
the left-to-right answer is already clamped, and a reflection of something
inside the box is inside the box.

This was carried by nothing for a long time. `direction`, `leading_alignment`,
`trailing_alignment` and `mirror_x` have existed since localization landed, and
the retained painter consulted none of them; the only caller outside this
module's own test was text layout, which takes a direction for the caret, hit
testing and selection. So an Arabic build got a correctly mirrored caret inside
a field whose checkbox was still nailed to the left with its label running away
from it. A policy nothing consults is a policy that is not there.

**Still left-to-right**: a slider's fill direction, and the side a scrollbar
sits on. Both are deliberate omissions rather than oversights — each maps
pointer coordinates back to a value or an offset, so mirroring the paint
without mirroring that mapping in the same change would invert the drag. They
want the painter and `ui_flat_pointer.elisa` moved together.
