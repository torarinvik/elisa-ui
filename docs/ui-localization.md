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

A **slider** and a **progress track** fill from the reader's start edge, and a
vertical **scrollbar** sits on the reader's trailing side. These needed the
painter and the pointer moved together — each maps pointer coordinates back to
a value or an offset, and mirroring the paint alone would leave the thumb where
the finger is not, which is worse than not mirroring at all. Both halves call
one `track_fraction`, which is its own inverse, so there is no second formula
to get wrong.

The scrollbar's x had been written twice, once in the painter and once in the
hit test. That is the shape a drift takes — a scrollbar you can see and a
scrollbar you can grab, in different places — and it is also the only thing
that had to change to move the bar, so having to change it twice is how that
lands as a bug rather than as a feature. It is said once now.

One trap worth naming, because a test walked straight into it: the span a value
fills runs from the reader's start edge to the thumb, so **its width is the
value in either direction and only its origin moves**. Mirroring the width
instead looks right at both ends and is inverted everywhere between — an empty
track paints itself full — and a check that only compares filled *fractions*
passes straight through it. Width and origin are asserted separately.
