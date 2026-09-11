# A ramp and a light

Two things every surface in a current interface has, and this framework could
not draw either.

A **ramp** — a linear gradient across a fill — is not decoration. Every raised,
tinted or accented surface in the interfaces this is being measured against is
one, and a framework that can only fill flat colour cannot draw one however
good its shadows are. Skia had `fill_linear_gradient` as an *immediate*,
Skia-only escape hatch that never entered the retained command stream, so no
widget on any backend could have a gradient.

A **glow** is not a shadow, and that difference is the whole policy:

|  | shadow | glow |
| --- | --- | --- |
| says | how high it is | that it is **on** |
| direction | dropped | centred |
| colour | black | the surface's own |
| grows with | the object, physically | the object, but wider |

They are drawn by the same primitive and mean opposite things, which is exactly
why the geometry lives in `UiPaint::glow_shadow` and not in five backends.

## SurfaceStyle

`fill_rect` began as `(box, color, depth)`, grew `corner` beside it, and the
next two attributes would have made it a six-argument call every backend has to
thread. `UiCore::SurfaceStyle` is the honest shape: facts about **one** surface
that travel together, named rather than positional, so a painter that ignores
three of them ignores them by name.

```
depth                the lighting
corner               the shape                (see docs/ui-shape.md)
gradient             the far end of the ramp  (alpha 0 = flat)
gradient_horizontal  which way it runs
glow                 the outer light          (alpha 0 = none)
```

It rides side-band, exactly as the depth alone used to — the command **payload**
is unchanged, so a wire backend that never learns about any of this keeps
decoding the same rectangles it always did. **A zeroed record is the old
behaviour exactly**, which is why this reached every existing call site without
touching one of them.

`UiCore::fill_styled` emits it; `UiFlat::set_gradient` / `set_glow` and their
`UiHandles` forwarders state it per widget; `UiFlat::fill_widget_surface` emits
the plain command when a widget stated nothing, so fixtures and the wire format
stay stable for everything that predates this.

## Per backend

| backend | ramp | glow |
| --- | --- | --- |
| Skia | yes, `fill_round_rect_gradient` | yes, coloured shadow |
| AppKit canvas | yes, clipped `CGGradient`, three stops, either axis | yes, core and halo |
| UIKit canvas | same as AppKit | same as AppKit |
| SDL3 | no — flat fill, as it already ignores depth | no |
| wasm wire | no — the host canvas owns treatment | no |


Quartz also hangs a shadow off a *drawing op* rather than drawing it as a
shape, so a glow there is a fill of the surface's own path with the light
attached — covered immediately by the body fill that follows.

## What is asserted

In `test/skia_painter/vocabulary.elisa`: that a glow is offset in neither
direction, spreads further than the shadow it replaces, keeps the surface's
corner, carries nothing but light, and cannot be asked for an unbounded blur;
that a zeroed record has neither attribute; and end to end, that the painter
fills a ramp from the widget's colour to the far one and asks Skia for the
light **in the colour it was given**.

One of those checks was written wrong first and is worth recording. `the
painter fills a ramp` originally asserted `rounded_gradient_count >= 1` — and
passed with the ramp removed, because a raised surface's **sheen** is a rounded
gradient too and is drawn right after the fill. The shim now keeps the *first*
rounded gradient of a frame, which is the fill; a count could never have told
the two apart.

## A light has a core and a halo

The way a shadow has a contact layer and an ambient one. One wide Gaussian at
the application's alpha is a haze — it reads as a tint *around* the object
rather than as the object being bright. `UiPaint::glow_core` is a second,
tight layer at a fraction of the halo's blur, drawn last; the two compound near
the edge and fall away together, which is what says the light is coming *from*
the surface. Every painter that draws a glow draws both.

## "No ramp" and "a ramp to nothing" are different statements

The far colour's alpha used to be the sentinel — alpha zero meant a flat fill —
and that conflated the two. A **scrim** over a picture, so that copy laid across
it reads, is a ramp from a deep colour to *fully transparent*; under the old
sentinel it was silently a flat wash at the near colour's alpha. The hero in the
storefront came out uniformly dark with its picture never showing, and the ramp
was doing exactly what it had been told.

`SurfaceStyle.ramped` is the flag now, the far colour is free to be anything,
and `UiFlat::clear_gradient` is the way back to a flat fill. A zeroed record
still means no ramp — `false` is zero — so nothing that predates this changed.

**And then the same symptom came back, from the other end.** The hero went dark
again on both CoreGraphics painters, with the ramp now saying exactly the right
thing. Quartz cannot shade a fill and shadow it in one op, so those painters
drew the surface twice: the flat body with the shadow attached, then the ramp
clipped over it. That is invisible while the ramp ends opaque and fatal the
moment it ends transparent — the far end reveals not the picture but the flat
slab of near colour the first pass laid down. Skia never had the problem
because there the ramp **is** the fill: one `fill_round_rect_gradient` call, no
body underneath it. The CoreGraphics painters now say the same thing: when a
surface has a ramp, the shadows are drawn as shadows *alone* —
`draw_shadow_outside`, the shape filled with its shadow attached and clipped to
everything outside the shape, so the fill lands nowhere and only what it casts
survives — and the ramp is the only thing that fills the shape. The glow takes
the same route for the same reason: its light was a fill of the surface's own
path, relying on the body to cover it, and a ramp that ends transparent covers
nothing.

The rule, stated once: **on a surface with a ramp, nothing but the ramp may
paint inside the shape before the ramp does.**

## Three stops, a halo, and a fit

**Two colours make a line.** The surfaces in a current interface are curves —
a lift at the top edge, the hue through the body, a deep end — and a scrim is a
falloff, not a slope. `SurfaceStyle.gradient_mid` / `gradient_mid_at` is a
middle stop at a position in (0, 1); zero means none, so a zeroed record is
still a two-stop ramp. Skia draws it through a packed-ARGB three-stop entry and
the CoreGraphics painters through a three-stop `CGGradient` on either axis, so
all three now draw the middle.

**A halo behind a run** (`TextRun.halo`) is the same glyphs blurred, drawn
*first*, so it follows the letterforms rather than boxing them — a headline
sits on a picture, a dark caption sits on glass. Sigma scales with the size.
Costs no layout. `UiFlat::set_text_halo` states it per widget.

**How a picture meets a box that is not its shape** (`ImageDraw.fit`, named
`PictureFit` because the Skia layer already had an `ImageFit` for its immediate
path and the stage1 backend declines a field expression where the two names
meet). Stretch is the default and what a photograph never wants; Cover fills
and crops, Contain shows all of it. The painter alone knows the picture's own
size — the host tells the resource at bind time — so the fit rides on the
command and the crop is decided at replay.

## Tracking

`TextRun.tracking` is an extra advance after every scalar but the last. It
*changes advances*, so it is the one text attribute that touches measurement:
`UiCore::tracking_width` adds exactly the term the painter adds — count minus
one, times the tracking — and the Skia shim advances scalar by scalar when it is
set, so a tracked run measures as it draws. It counts scalars, not bytes. Labels
only: `UiFlat::set_text_tracking` refuses everything else, because a control's
caption is centred in a declared box and would not move.

## The CoreGraphics painters, caught up

Everything above is now drawn by the AppKit and UIKit canvases as well as by
Skia: three-stop ramps on either axis, the glass edges (an even-odd fill of the
shape's outside with a shadow attached, clipped to the shape), the halo (a
second `CTLineDraw` with a zero-offset shadow, drawn first), tracking (a kern
attribute — CoreText adds it after every glyph, Elisa measures it after every
glyph but the last, so a tracked line is drawn one gap longer at its trailing
edge, where nothing is measured against it), and retained images through a
per-painter slot/generation table, `CGContextDrawImage` under the y-flip a
CGImage needs, `CGContextDrawTiledImage` for `Tile`, and the fit policy that
now lives in `UiPaint::fitted_rect` so all three painters share it.

Font fallback on CoreGraphics is CoreText's own cascade and needed nothing.

Two things the build found. The AppKit+Skia compositor compiles both painters
into one unit, and a CG function named the same as a Skia one was declined
there — renamed. And the painter must not depend on the resource subsystem: the
simulator smoke unit does not carry it, so the CG binding table takes a slot
and a generation, the two numbers the command already has.

`appkit_canvas_surface_test` sampled the *foot* of a translucent raised surface
to prove it was filled once; the foot now carries a deliberate shaded edge, so
it samples the centre, which a double fill still darkens.
