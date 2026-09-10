# Motion

A control moves between its states instead of jumping between them. Hover,
press, disable and selection all resolve to a surface colour, and the colour on
screen travels to the new one over `UiFlat::STATE_TRANSITION_SECONDS` — 0.14s,
which is where a control-sized change lands in every system worth copying.

## Why the framework and not the application

Every state a widget has already lives in `UiFlat`: hovered, pressed, enabled,
selected, and the colour each of them resolves to. An application that wanted
its buttons to ease under the pointer would have to duplicate that resolution,
keep its own copy of the previous colour for all 256 widgets, and drive a frame
clock. It would also have to re-derive the accessibility answer, and get it
right: a reduced-motion preference has to remove the motion and change nothing
else about where the control ends up.

## Why a clock is the switch

`UiCore::set_frame_time` is optional, and documented as optional — *platforms
that do not animate may leave the default at zero*. A host that leaves it there
measures a zero interval, every transition completes in the frame it starts,
and the picture is identical to the one the framework drew before transitions
existed. That is why adding them changed no existing test and no rendered
fixture: the offscreen showcase renderer reports no clock.

Motion is what a host opts into by telling the framework what time it is. The
AppKit canvas, the AppKit/Skia compositor, UIKit, SDL3 and the browser runtime
all already did.

## What travels and what does not

Colour travels. **Depth does not**: a button being pressed is *in* the surface
from the first frame of the press, because that is what it is — only its colour
has any distance to cover. Paint reads the state for `surface_depth_of` and the
screen for the fill, which is the one place those two facts differ.

Geometry does not travel either. Nothing in the layout pass is interpolated, so
a transition can never move a hit target out from under the pointer that
started it.

## The interval, not the frame

The step is a fraction of the remaining distance, so a control eases in rather
than arriving at constant speed, and the fraction comes from elapsed **time**:
a 30Hz host and a 120Hz one take the same 0.14s, and a frame the host was late
for covers the ground it missed.

A channel that differs always moves by at least one level. A proportional step
over a short distance rounds back to where it started, and a transition that
cannot make progress asks for a wake it will waste and never finishes — the
control would sit one level short of its state for as long as the window is
open.

A control in motion calls `UiCore::request_frame_after`; hosts coalesce onto the
earliest request, so a page of moving controls is still one wake. A settled one
asks for nothing, which is what keeps an idle window idle.

## Reduced motion

`UiTheme::animation_interval` returns zero under a reduced-motion preference,
and a zero duration is a completed transition. The control reaches the same
colour on the same frame as it always would; it simply does not travel. This is
the same policy the caret blink and the frame scheduler read, so there is one
answer to "does this window animate" rather than one per feature.

## What is asserted

`test/widget_motion_test.elisa`. A transition is the one thing no still frame
can show, so it is asserted rather than looked at: that a clockless host paints
the settled colour, that a widget's first frame is its own colour rather than a
fade in from nothing, that one frame into a transition the surface is strictly
between its two states, that depth is already the new one, that it finishes
exactly on its target rather than near it, that a settled control asks for no
further frames, and that reduced motion arrives without travelling.
