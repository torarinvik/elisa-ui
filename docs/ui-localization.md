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

## What the painter mirrors

A choice control's **hit target** needed nothing: the whole row is the target
in both directions, and hit testing never consults the marker's geometry. It is
recorded here because it looked like work and was not — checking was cheaper
than the change would have been.

## What the sizer mirrors

Everything above moves content around *inside* a box. None of it moves the box.

That distinction was invisible while every fixture measured a caret's x, a
marker's side or a label's origin — quantities that all live inside one
widget's frame — and it stayed invisible until a right-to-left frame was
rendered and looked at. The picture was mirrored by halves: section headings,
field text, checkbox markers and the status line all sat at the reader's edge,
while the fields, radio rows and buttons they belonged to were still hard
against the opposite one, with the empty half of the card between them. That is
not a right-to-left layout. It is two layouts in one frame.

Both layers now mirror the **placement of a child inside its container**, and
in both it is one reflection of the child's box within the container's content
span:

```
mirrored_x = inner_x + span - (child_x - inner_x) - child_width
```

One line covers cases that would otherwise each want a rule: a row's siblings
come out in the opposite order, a column's start-aligned child moves to the
trailing edge, the sealed hierarchy's grid cells reverse across each line, and
a scrolled row travels the other way — the last one for free, because a
scrolled child arrives at the reflection with its translation already applied.
Reflecting rather than recomputing also keeps the child inside its container
without a clamp, for the same reason the marker stays inside its control.

The reflection composes with the paint-time mirroring above rather than
competing with it: one decides where the box goes, the other where the content
sits inside it, and neither can mirror the other's quantity twice.

Hit testing follows for nothing, because both layers hit-test against the same
stored frames the sizer wrote. A control you can see in one place and grab in
another is worse than one that was never mirrored, so both fixtures assert the
pointer at the mirrored coordinate rather than trusting that.

The showcase now renders a right-to-left frame with the real renderer, and the
gate requires it to differ from the left-to-right one — a locale that reached
nothing still writes a perfectly good left-to-right picture, which is exactly
the failure that had to be caught by eye the first time.

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

An ordinary **label** starts at the reader's own edge. The default alignment
for content was written as "leading" in the comment beside it and implemented
as `x` — one word doing duty for two different edges, and correct for one of
them. Reading as a decision rather than an oversight is how it survived the
change that taught the marker beside it which side it was on. A run wider than
its box keeps the leading edge in both directions: pushing it off the start to
honour the end is how a long label becomes an unreadable one.

A **slider** and a **progress track** fill from the reader's start edge, and a
vertical **scrollbar** sits on the reader's trailing side. A **horizontal**
scrollbar needed more than a side: a row viewport has a direction of *travel*,
so a mirrored one parks its thumb at the reader's own edge and runs it the
other way, and the drag delta changes sign to match. Reverting either half
alone fails its own assertion — the paint half leaves the thumb parked at the
wrong end, the drag half sends it away from the finger. These needed the
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

A **text field's content** follows the reader: the run starts at the reader's
own edge, and the caret, the selection band, the composition underline and the
click that places the caret all follow it. This is the one piece that could not
be a reflection — but it turned out not to need five mirrorings either.
Everything a field draws or hits is a *distance from the start of the visible
run*, and direction changes exactly one thing: which edge that run starts at.
One pair of inverse functions (`field_run_x` and `field_run_distance`) carries
all of it, so the painter and the pointer have no second formula to disagree
about. A span is drawn from its leading corner, which for a mirrored reader is
the far end of the distance it covers; a caret is the zero-width case and needs
no special handling.

These helpers live in `ui_flat_direction.elisa` rather than beside the colour
policy. Each of them is the single place its two consumers meet, and that
matters more here than elsewhere: a second copy of any one is a control you can
see in one place and grab in another.

## Both widget layers

The sealed hierarchy in `ui_hierarchy.elisa` has its own painter, and it had
heard none of this: every run was drawn at its box's left edge and every fill
grew from it. Labels, text boxes and button captions now start at the reader's
edge there too, a gauge fills from it, and a slider's knob travels from it.

Two widget layers that disagree about which way the reader reads is worse than
one layer that is simply wrong, because only one of them looks broken and the
bug becomes a property of which API an application happened to pick.

That layer's slider and gauge are display-only — neither appears in its pointer
or hit-testing files — so unlike the flat layer's, mirroring the knob had no
second half to keep in step with it. That was worth checking rather than
assuming: it is the difference between a two-line change and the paired one the
flat slider needed.

## Native controls

Absolute placement forfeited RTL mirroring, and `ui_controls.elisa` said so in
its own header two paragraphs after claiming the platform provided it. Only the
second statement was true: an Arabic build got its controls in left-to-right
order, each one correctly mirrored *inside itself* by the OS — the worst of the
two arrangements, because every control looked right and the layout was
backwards.

A box mirrors inside its **parent**, so `mirror_control_boxes` is two sweeps
over a list that is already in parent-first order: one to record how far each
control sits from its container's leading edge, and one to place it that far
from the other edge. Doing it inside the tree walk would need a parent's
original box after its own had been overwritten. A full-width child mirrors to
nowhere, which is correct and asserted; the root has no container and is left
alone.
