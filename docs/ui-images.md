# Retained images

Images were the last thing in this framework a widget could not have.

They existed only as an **immediate, Skia-only facility** — a call you make into
a live canvas, outside the retained command list every backend replays. The
widget layer never makes immediate calls, so no widget on any backend could
carry a picture, and every icon, thumbnail and avatar in a real interface was
out of reach. The command list is the only thing a backend replays: anything
not in it does not exist as far as the framework is concerned.

## A slot and a generation, not a pointer

```
UiCore::ImageRef { slot: u32, generation: u32 }
```

The retained command list is plain data — it can be asserted in a test with no
renderer, logged, diffed between runs, or shipped across a boundary no native
handle could cross. A raw `SkImage*` in it would end all four, and would make
the list unsafe to keep for even one frame past the image's life.

A slot names *which* image; a generation says *which one that was*. Reusing a
slot after the first image is gone bumps the generation, so a command left over
from a previous frame resolves to nothing rather than to whatever moved in.
That is the shape `UiResources` already uses, so the two need no translation.

**Generation zero is the sentinel.** A resource subsystem issues its first
generation at one, so a zeroed record — an uninitialised widget row, a cleared
command slot — names no image *by construction* rather than by convention.

## The command

`Command.DrawImage(draw: ImageDraw)` is the one arm that carries a whole record
rather than a shape and a colour: an image has no colour, and everything it
does need travels together.

```
box     where it goes
image   which picture
alpha   per-DRAW, not per-image
corner  which corners to cut
```

The alpha is per-draw because the same picture fades in on one surface while
sitting solid on another, and an image reloaded to change its opacity would be
a cache miss disguised as an animation. `corner` lives here rather than in
`SurfaceStyle` because an image is not a surface: it has no depth, casts
nothing, and the only thing it borrows from the shape vocabulary is which
corners to cut.

## Per backend

| backend | draws it |
| --- | --- |
| Skia | yes — resolves the reference through its existing binding table |
| AppKit / UIKit canvas | no |
| SDL3 | no |
| wasm wire | encodes it; the host canvas decides |

**A backend that cannot draw an image draws nothing** — no placeholder. A grey
rectangle where a thumbnail should be is a worse frame than a gap, and it hides
the fact that the image never arrived.

The wasm painter is the exception that proves the rule about the wire: it
cannot draw an image either, but it **must still write a record**, because the
host is handed a *count*. A command that writes no record leaves the host
reading one slot of whatever was there last frame. The wire is additive —
discriminant 6, every other record byte-identical at the same offsets — so a
host built before images existed skips it by its unknown tag.

## On a widget

`UiFlat::set_image` / `set_image_alpha` and their `UiHandles` forwarders. The
picture is painted **over the fill and under the text**: a picture is not a
surface, it sits on one, and anything the widget has to say still goes on top.

A disabled control's picture recedes with it, for the same reason its ramp and
its glow are dropped — what the reader sees has to say whether the control will
answer.

`UiFlat::set_min_size` arrived with this and is unrelated except by need: every
builder that takes a minimum takes it once at construction and a panel takes
none, so a container meant to hold a fixed square had no way to say so and came
out zero-sized. It refuses on a **label**, whose minimum is remeasured from its
text every layout pass — a value set there would be overwritten before it was
used, and silently.

## What is asserted

`test/widget_image_test.elisa`: that a widget with no picture emits no image
command, that one with a picture emits it into its own box with the reference
the application gave, at full strength by default, dimmed when disabled, and
that a reference to nothing draws nothing.

The showcase gate samples the application's mark before and after the host
binds a picture and requires it to change. A binding that fails silently, a
command the painter drops, a reference that resolves to nothing — each produces
a perfectly good frame with an empty tile, which is exactly what a file-size
check cannot tell from a full one.

The picture in that fixture is **made, not loaded**: a diagonal ramp with a
lighter wedge, built in the host. What is being proved is that an image reaches
a retained widget, not that a PNG can be decoded.
