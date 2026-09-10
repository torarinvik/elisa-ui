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

## The focus ring

It is a rounded fill drawn UNDER the control, slightly larger — a halo, not an
outline. The retained command vocabulary has no stroked rounded rectangle, so
an outline could not follow the shape it was outlining, and the ring was four
straight lines with square corners on every rounded control. A fill behind the
control is rounded by the same policy that rounds the control, so the ring is
concentric by construction in every backend, with no change to the wire format
the hosted backend encodes.

A stroked-rounded-rectangle command is still the missing primitive; bordered
cards and outlined buttons want it too.

## Backends

The policy is shared: `UiPaint::RoundedRectStyle` is what every custom backend
reads. The Skia painter draws all of it. The AppKit and UIKit CoreGraphics
painters currently draw the shadow and the hairline and ignore the sheen and
bevel fields, so they render as they did before rather than incorrectly.
