# Shape is a statement about kind, not only about size

The corner policy in `ui_paint.elisa` derives a radius from the box, and it is
a good default *because* it is derived: every surface in a frame stays
consistent with every other without an application naming a pixel value that
stops being right at the next text scale.

But two surfaces of the same size can be different kinds, and until now there
was no way to say so — a radius came from the box and from nothing else. A tag,
a status chip and a count badge are capsules at a size where the derived policy
asks *"is this a bar — long **and** thin?"* and correctly answers no. That is
not a flaw in the policy; it is a fact the policy cannot know. **A capsule was
not expressible at all.**

## Three kinds, not a radius

```
UiCore::CornerStyle.Automatic   the derived policy
UiCore::CornerStyle.Pill        always a capsule
UiCore::CornerStyle.Square      no rounding
```

Deliberately a kind rather than a number. A number invites an application to
hardcode `8.0` and drift away from the rest of the frame; a kind stays right
when the metrics change under it.

`Pill` asks for half the short side, which is exactly what
`rounded_rect_style_with_radius` already clamps to — so a capsule needs no
separate arithmetic and cannot exceed its box, in either orientation.

## How it travels

Side-band, like the surface depth and the stroke width beside it:
`command_corner_style[]`. The command **payload** is unchanged, so a wire
backend that never learns about shape keeps decoding the same rectangles it
always did.

- `UiCore::fill_shaped(box, color, depth, corner)` emits it. Every other fill
  is this call with `Automatic`, which is why nothing else had to change.
- `P.fill_rect` gained the parameter, and the three painters that compute a
  style call `UiPaint::rounded_rect_style_for_shaped`. One line each. SDL3 and
  the wasm wire ignore it exactly as they already ignore depth.
- `UiFlat::set_corner` / `UiHandles::set_corner` state it per widget.

## Used, not merely offered

The showcase's row-count badge on the Lists page is a capsule. A flag with no
caller is the shape every defect in this work has had, so the feature ships
with one.
