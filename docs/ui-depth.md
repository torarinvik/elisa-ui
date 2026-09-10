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

- **shadow** — what lifts a LIGHT surface. Wide and soft; a tight dark smudge
  reads as a border rather than as height.
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

## Which widgets are which

`UiFlat` decides, in `surface_depth_of`:

- Buttons, radios and checkboxes are **raised** — you press them.
- Text fields are **inset**.
- A `Panel` is a card when its colour differs from the ground behind it, and a
  layout box when it matches. Panel is both in this model, and nothing else
  distinguishes them; elevating all of them would put a shadow behind every
  row. The ground is the first ANCESTOR that actually paints, not the immediate
  parent — a row is usually transparent, and a card inside one sits on whatever
  is behind the row.
- A card lighter than its ground is raised; darker is recessed.

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

The one thing a backend may still legitimately differ on is text weight, because
the font stacks differ: Skia synthesizes it with `SkFont::setEmbolden`, CoreText
asks for the bold symbolic trait. Both now read `TextRun.weighted`; CoreText used
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

Skia has no bold face to select. A host lends the renderer one borrowed
typeface, so weight there is synthesized -- and the AMOUNT is now the
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
