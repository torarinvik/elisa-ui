# Overlays: a modal is a sheet over a shell that has receded

Roots in the flat layer paint in arena order, so *"paint this last"* was always
expressible. The other half of what a modal **is** was not, and it shows: every
frame this framework has ever rendered of its own confirmation dialog was a
band glued into the layout, sitting above a shell that still looked entirely
clickable.

## The flag

`UiFlat::set_overlay(index, true)` marks a **root** as an overlay. Only a root
can be one — an overlay nested inside the tree it is meant to cover would have
to be painted out of its own subtree's order, and that is a second paint order,
not a flag. `UiHandles::set_overlay` forwards it.

A root always fills the viewport, so an overlay in practice is a transparent
full-bleed layer that holds the sheet. That is what makes the sheet centreable
and the wash full-bleed without either being a special case: put the sheet
inside the layer, give the *sheet* `CrossAlignment.Center` (cross alignment is
a property of the child, not the container — setting it on the layer leaves the
sheet stretched to the full width of the window, which is a band with a scrim
behind it) and the layer `MainAlignment.Center`.

## One query, two consumers

`overlay_paint_start()` returns the paint-order position of the first visible
overlay root. The painter lays `theme().scrim` across the viewport when it
reaches that position — **between** the shell and the sheet, in the paint
order, so it dims exactly what is under the sheet and nothing else. A wash in
front of the sheet is a fog; one behind the shell dims nothing.

The pointer stops its reverse walk at the same position. This is not a nicety:
a scrim is the *picture* of the fact that everything under it is inert, and a
shell that is dimmed in the frame and still live under the finger is worse than
one that was never dimmed. One query means the two cannot disagree about where
the wash begins.

A hidden overlay is not an overlay — the wash leaves with the sheet.

## The token

`Theme.scrim` is black at 43%. A scrim darkens on **both** palettes: on paper
that is the shadow of the sheet falling across the page, and on a dark ground
it is still the only direction that works, because a light wash over a dark
page *lifts* what it is meant to push back. Transparent means an application
wants none.

## What is asserted, and where

The command-level facts are in `widget_layout_geometry_test`: that a scrim
appears only when something is overlaid, that it covers the whole viewport,
that it lands between the shell's fill and the sheet's, that the pointer
returns nothing over the covered region and still reaches the sheet, that a
hidden overlay takes its wash with it, and that a child is refused the flag.
Removing the emission reddens two of those; removing the pointer floor reddens
another.

The showcase gate checks that the shell recedes when the dialog opens (35 to 11
in the rendered frame). Honest about what that catches: the showcase *also*
disables its shell while a modal is open, and disabled surfaces mute, so the
gate fires if the page stops receding for either reason. It is a regression
guard, not proof that a wash was laid.

## Not yet

The sealed hierarchy (`UiWidgets`) has no overlay flag. Its paint pass has the
same shape, so the same query would fit, but nothing in the shipped surface
uses it for a modal today and a flag with no caller is the shape every defect
in this work has had.
