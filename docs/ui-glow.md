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
| AppKit canvas | yes, clipped `CGGradient` — **vertical only** | yes, coloured `CGContextSetShadowWithColor` |
| UIKit canvas | same as AppKit | same as AppKit |
| SDL3 | no — flat fill, as it already ignores depth | no |
| wasm wire | no — the host canvas owns treatment | no |

The CoreGraphics painters have a `vertical_gradient` helper and no horizontal
one, so `gradient_horizontal` is ignored there and the ramp runs vertically.
Recorded rather than hidden: it is a real difference between the frames those
two backends and Skia produce.

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
