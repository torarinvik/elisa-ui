# Depth and lighting

A surface in this framework is one of three things, and it says which:

    UiCore::fill(box, colour)            # flat
    UiCore::fill_elevated(box, colour)   # raised
    UiCore::fill_inset(box, colour)      # recessed

`UiCore::SurfaceDepth` rides beside the command in the retained buffer, and the
shared policy in `UiPaint` turns it into the effects a custom backend draws.

## Why three, and not a shadow flag

Raised and inset are not two shadows. They are opposite lighting.

A raised surface catches light on its top edge and drops a shadow below it. A
recess is lit along its BOTTOM edge and shaded at the top, because the light is
still overhead and the near wall has become the far one. Painting a text field
with the raised treatment is the most common way an interface looks almost
right and slightly wrong: a field you type into is cut into the surface, not
resting on it. The same is true of a slider track and a progress track — both
are grooves, and the value that fills them sits IN the channel rather than
being another surface stacked on it.

## Why the colour is an argument

`rounded_rect_style_for(box, depth, colour)` takes the colour that will be
painted, and weights three effects by its perceived lightness (Rec. 601, so a
saturated accent is correctly treated as a dark surface rather than a mid-grey):

- **shadow** — what lifts a LIGHT surface, in two layers. A wide, soft
  *ambient* shadow is the room's light; a tight, dark *contact* shadow is the
  sliver of space the object does not quite close. One blur alone is a
  drop-shadow filter: drop the contact layer and the object floats, drop the
  ambient and it looks stamped on.
- **sheen** — a white wash across the face, strongest at the top. The surface is
  lit from above.
- **bevel** — the rim of that light on the top edge. One pixel, and the
  difference between a rectangle and an object.

On a dark interface a drop shadow is nearly invisible, so a dark surface leans
on the sheen and the rim; on a light one the shadow does most of the work. The
style used to be chosen without knowing what would be painted into it, so one
shadow served a white card and a near-black panel and suited neither.

An inset surface inverts the last two: the wash is shade rather than sheen, and
the rim moves to the bottom. It casts no shadow of its own — the shadow is
inside it.

## Why the box is an argument too

Both shadow layers scale with the surface's shorter side, clamped at both ends.
They used to be four constants — 8pt down and 22pt across for everything — so a
34pt button and a 600pt sheet were lit by the same lamp at the same distance.
On the button that is a shadow larger than the object, which does not read as
height but as haze; on the light palette it spread the alpha thin enough that
the column of pixels under a button measured as flat background.

The shorter side is the right measurement because a full-width toolbar is not
lifted further off the page by being wide, and a tall narrow panel is not lifted
by being tall. The clamps are what stop a bar from casting a fifty-pixel shadow.

## Glass

A **raised** surface with a **translucent** fill is glass: the framework blurs
whatever is already on the canvas inside its outline before filling it. That is
what vibrancy, acrylic and `backdrop-filter` are for, and it needs no new API —
an application that puts an alpha below 255 on a lifted panel has already said
"a panel floating above content you can still see."

The other three cases are deliberately not glass. An opaque panel has nothing
to show through it. A recess is *in* the surface it is cut from. And a flat
translucent fill is a tint — the framework paints those by the hundred, and
blurring behind each one would be an effect nobody asked for.

Unlike the shadow, the blur radius does **not** scale with the surface. A
shadow scales because the height it implies is physical; a blur radius is a
property of the *material*, and two panels cut from the same glass frost
identically. `BACKDROP_BLUR_SIGMA` is 6 — a Gaussian spanning roughly forty
device pixels end to end, far enough that text behind the panel stops being
legible and close enough that blocks of colour survive as the shapes they are.
The one concession to size is a cap at about a third of the surface's shorter
side: a blur wider than the panel samples what is *beside* it rather than
behind it, and reads as a wash.

This is the only effect in the framework that is a function of the pixels under
a surface rather than of the surface, and so the only one a backend cannot
compose from the primitives it already had.
`elisa_skia_canvas_blur_behind_round_rect` is the whole addition (ABI 0.6.0).
Quartz has no comparable backdrop filter without an offscreen round trip, so on
the CoreGraphics painters a translucent raised surface is plain translucency —
named here rather than left to be discovered.

## An outer shadow is outside

The part of a drop shadow that falls under the surface is invisible while the
surface is opaque and is a *stain* the moment it is not: the first glass panel
rendered came out at luminance 42 where it should have been 99, darkened by its
own shadow showing through it. CSS clips an outer `box-shadow` out of the border
box for exactly this reason, and the Skia painter now does the same. It costs
nothing in the opaque case, where those pixels were being covered anyway.

## Which widgets are which

`UiFlat` decides, in `surface_depth_of`:

- Buttons are **raised** — you press them — and go **inset** while they are
  being pressed. Pressing used to be a colour swap and nothing else, which is
  the feedback a hyperlink gives; the opposite lighting direction this policy
  has always carried was written for grooves and never asked for by the one
  gesture it describes exactly.
- A disabled control is **flat**. Elevation is an invitation, and one that
  still stands off the page is inviting a press it will not answer. It is also
  muted *toward the surface it sits on*, not toward black. Halving every
  channel was the old rule, and it reads as "off" on a dark interface only by
  accident — everything there is already near black, so darkening happens to
  lower contrast. On a light page the same rule turns a near-white button
  mid-grey and makes the one control that must recede the most prominent thing
  on the screen. Half the distance to the ground is the same statement in both
  palettes: less difference from the surroundings. A mark, a track or a caption
  recedes into the widget's own fill rather than into what is behind the widget,
  because a disabled checkmark fading toward the page would *gain* contrast.
- Radios and checkboxes are **flat**, and inset while pressed. They were raised
  like buttons until a list of twenty-four full-width rows showed what that
  costs: each row with its own rim and its own shadow is a ladder of floating
  buttons rather than a list. Nothing about the widget says which it is — the
  same radio is a segmented option in a form and a row in a list — and the
  framework cannot see that the rows are adjacent. What it can say is that a
  choice is announced by its MARKER; the surface behind it is a hit target, and
  a hit target need not stand off the page to be pressable. Elevation is for
  what you press, not for what you choose.
- Text fields are **inset**.
- A `Panel` is a card when its colour differs from the ground behind it, and a
  layout box when it matches. Panel is both in this model, and nothing else
  distinguishes them; elevating all of them would put a shadow behind every
  row. The ground is the first ANCESTOR that actually paints, not the immediate
  parent — a row is usually transparent, and a card inside one sits on whatever
  is behind the row.
- A card lighter than its ground is raised; darker is recessed.

A choice control's label is leading-aligned immediately after its marker. It
used to be centred in whatever room the marker left, which floats the words away
from the box they name and makes a column of switches read as a column of
buttons. The centring was also concealing a token that had drifted out of
meaning: `apply_metrics` set `choice_text_space` to the raw spacing unit — 8pt
at the default — while the marker's centre sits at 13.5 with a radius of 5.5, so
a leading-aligned label would have been drawn straight through the box it names.
The marker's centre and the label's origin are one measurement now, and the gap
on either side of the marker is one spacing unit at any accessibility scale.

## Rings

A ring is a rounded fill drawn UNDER a widget, slightly larger — a halo, not an
outline. The retained command vocabulary has no stroked rounded rectangle, so an
outline could not follow the shape it was outlining, and every ring in this
framework was four straight lines with square corners on a rounded control. A
fill behind the widget is rounded by the same policy that rounds the widget, so
the ring is concentric by construction in every backend, with no change to the
wire format the hosted backend encodes.

The focus ring is one instance. An application asks for its own with

    UiHandles::set_ring(handle, colour)

for a modal's accent frame, a validation error, a tour highlight. Focus wins
where both apply: where a keyboard user is standing is the more urgent fact, and
two concentric rings read as neither. A transparent colour is no ring.

A halo drawn straight against the control is not always a ring. The showcase's
primary action is filled with the same accent the theme derives its focus ring
from, so an accent band laid against it says nothing — it is a slightly wider
button. A browser buys the separation with `outline-offset`, which is not
available here: a retained widget does not know what is behind it and would have
to guess a colour to punch through to. So the ring carries a one-pixel
separator, in ink chosen by the control's own lightness — the same rule that
picks the mark on a filled checkbox — with the accent band keeping its full
themed width outside it.

It has to be the painter's job rather than an app's frame callback, for two
reasons that only show up when you render it. Drawn before the retained tree it
renders nothing — the shell and page panels paint after it and cover the
viewport. And it has to be positioned after layout, because the frame that opens
a dialog is the frame that first gives its panel a box.

A stroked-rounded-rectangle command is still the missing primitive; bordered
cards and outlined buttons want it too.

## What the gate looks at

`scripts/render_showcase_skia.sh` renders the shipped showcase through the real
painter and writes every frame to `build/`. The list is the point: each entry is
an appearance that was, at some stage, drawn by code no picture covered.

- five pages, dark
- `-light`, the light palette — the other half of the depth policy
- `-contrast`, the high-contrast palette at double text scale — the
  accessibility branch, which nothing had ever put on screen. Every bug found
  in that path had been found by reading rather than by looking, and the first
  frame it produced showed a row of accent swatches drawing their rings over
  each other.
- `-focus`, with the keyboard focus on a control
- `-dialog`, a modal over a shell disabled beneath it
- `-hover` and `-pressed`, a control under the pointer
- `-retina`, at a 2x backing scale

Size floors catch a page that stopped laying out. The checks that earn their
keep are the ones that require frames to DIFFER: a focused frame identical to
the unfocused one means no ring was drawn, and a hovered frame identical to the
resting one means the pointer reached nothing. Both have fired.

## Backends

The policy is shared: `UiPaint::RoundedRectStyle` is what every custom backend
reads, and all three custom backends now draw all of it.

For a while only Skia did. The AppKit and UIKit painters asked for a style with
`rounded_rect_style(box, elevated)` -- no colour, so no weighting, and no way to
express a recess -- then drew two of the four effects the record describes and
dropped the sheen and the bevel on the floor. The same command list produced a
lit surface under Skia and a flat one under CoreGraphics, which is precisely the
drift the shared record exists to prevent.

What is shared is now the whole policy, not just the numbers. `UiPaint` owns the
derivations that used to live inside the Skia backend -- `has_sheen`, the tint
that inverts for a recess, and the rim gradient whose direction flips with
`bevel_at_bottom` -- so a backend contributes no appearance decision of its own.
What it contributes is a primitive: Skia takes a gradient-shaded round rect
directly, while Quartz has none and must clip to a path (and, for the rim, to a
stroked path converted into an area) and fill it. That difference is confined to
one function per backend.

The contact shadow needed no new vocabulary anywhere: it is a style whose shadow
fields are the contact ones, so each backend draws it with the shadow call it
already had. Skia draws both layers under one fill; CoreGraphics attaches a
shadow to a drawing OP, so the two layers are two fills of the same path, and
the second covers the first's body exactly — as long as that body is OPAQUE.
Filling a translucent surface twice composites its colour with itself, so the
CoreGraphics painters skip the contact layer when the fill is not opaque: a
visible bug is not worth an invisible shadow, and that is the one place the two
backends cannot draw the identical picture.

The one thing a backend may still legitimately differ on is text weight, because
the font stacks differ: Skia synthesizes it as a stroke added to the outline,
CoreText asks for the bold symbolic trait. Both now read `TextRun.weighted`; CoreText used
to infer weight from point size alone, so a weighted stat value came out bold in
one backend and regular in the other.

`test/appkit_canvas_surface_test.elisa` is what keeps this honest. It renders
through the real `AppKitPainter` into a CoreGraphics bitmap -- no window, no run
loop -- and reads the pixels back, asserting the same lighting relationships the
Skia hosts assert: raised is brighter at the top, a recess is the same
relationship inverted, flat is a weaker version of raised, and the rim is
brighter than the fill beneath it. Six of its seven checks fail against the
painter as it was. UIKit cannot be run on the build host, so it is held to the
compile gate and to being a mirror of the AppKit file -- the honest ceiling for
that backend, and the same one the rest of it has.

## Typography

Weight is a flag on the run, and only the flag. Both CoreText painters used to
read `run.weighted or run.size >= 19.0`; the size half was older than the flag
and outlived it, so a large label came out semibold on Apple platforms and
regular under Skia with nothing in the model saying which was meant. An app that
wants a heavy heading marks it.

That heuristic also lived in the MEASUREMENT seam, which is why removing it from
the painter alone would have been a bug: `ui_measure_text_width` inferred weight
from the point size exactly as the painter did, so the two agreed by accident.
Weight now travels with the run into both, and `UiTextMetrics` keys its cache on
it -- the same string at the same size measures differently bold, and a cache
that forgot which one it stored would hand a weighted run the regular width.
`set_text_weight` marks layout dirty for the same reason: on CoreText, weight is
a real semibold face and a label's intrinsic width changes with it.

Skia takes a designed bold face when the host lends one. `elisa_skia_set_bold_typeface`
is the whole addition (ABI 0.7.0): with a bold face in hand a weighted run is
drawn *and measured* with it, and the synthetic stem growth is not applied on
top — a designed bold already carries the weight in its outlines, and dilating
it as well would double the stems and close the counters. Every Skia host in
the tree lends the system bold from the same font manager it already asked for
the regular face. That is what keeps the AppKit/Skia compositor honest: it
MEASURES with CoreText, which picks the bold symbolic trait, and DRAWS with
Skia, so the two have to be handed faces from the same place.

`UiTextMetrics` was already keying its cache on weight; Skia's own metric cache
now does too. It did not have to while weight was a stroke — a stroke leaves
the advance alone, so bold and regular measured the same — and a cache that
forgot which one it stored would hand a weighted run the width of its regular
self and clip it.

The synthetic path remains, and is what a host with one typeface still gets.
A host lends the renderer one borrowed typeface, so weight there is synthesized -- and the AMOUNT is now the
framework's rather than Skia's. `setEmbolden` decided it before, and measured
against CoreText's semibold at the same size it was 30% light: a heading was
bold in a native AppKit window and merely medium in the Skia one. It is a stroke
added to the glyph outline instead, which also keeps the property the
single-typeface design rests on -- a stroke does not change the ADVANCE, so a
weighted run occupies the box the layout pass measured for it.

`SYNTHETIC_WEIGHT_RATIO` is tuned against that reference but deliberately not to
equal it. Matching its ink takes 0.07, and at 0.07 the counters close: dilating
one face uniformly is not what a designed bold does, so the bowl of an "e" fills
in before the stems are heavy enough. 0.045 is where a heading reads as bold and
the counters stay open. A real bold face would look better still and is what a
future host-lends-two-typefaces change would buy; it would also make advances
differ between the measuring and the drawing authority on the AppKit+Skia
product, where CoreText measures and Skia draws.

## A shadow lifts a surface; it must not stain the page

Measured against the interfaces this framework is aiming at, the light
palette's own frame was the tell. A white card darkened the page under its
edge by **66 levels** and was still **27 levels** dark 35pt away, and the
12pt gutter between two adjacent cards was filled by both their shadows at
once. The gaps in that frame did not read as the page; they read as grooves,
and a page of grooves is what makes an interface look a decade old.

Three numbers decided that, and all three lived here where no fixture could
see them — the painter shim discarded the shadow's alpha outright, which is
the one value that separates height from dirt. The alpha is recorded now, and
the policy is asserted directly:

| | before | after |
| --- | --- | --- |
| ambient alpha, light surface | 46 | 20 |
| contact alpha, light surface | 60 | 26 |
| ambient blur ratio | 0.30 | 0.13 |
| ambient blur floor / ceiling | 5 / 44 | 2 / 18 |
| ambient offset ceiling | 16 | 10 |

The **dark** end of every blend is untouched. A dark surface leans on the
sheen and the rim because a shadow has to survive being dark-on-dark, and a
fixture keeps the two ends ordered so a light-palette correction cannot
quietly flatten the other one.

Lowering the blur *floor* was forced by the ratio, not chosen: at 0.13 every
surface shorter than 38pt clamped to the same floor, so a 16pt slider thumb
and a 30pt button were lit identically and the existing "a shadow is the size
of the thing that casts it" check went red. A 2pt floor restores the ordering
and is the physically right answer anyway — a small object close to the page
has a tight shadow.

The sideways reach of a shadow is its blur, so that is the number a gutter
constrains, and it is now bounded below the tightest gutter the shipped
metrics produce.

