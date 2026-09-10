# The storefront example

A second example, and deliberately not a second showcase.

The showcase exists to put **every widget the framework has** on screen. That is
what makes it a coverage artifact, and it is also what makes it look like a
widget catalogue: a page of stat cards, a page of sliders, a page of rows. It
answers *what can this framework draw*.

The storefront answers the other question — **what does an interface built with
this framework look like** when it is composed the way a shipping application is
composed. There is nothing on screen to demonstrate a feature. A rail, a search
bar, a header with tabs, a hero, and a grid of cards.

`scripts/render_storefront_skia.sh` renders it with real Skia, off-screen.

## Every treatment is one call

That is the point of the preceding work, and the example is the proof:

| in the frame | how it is said |
| --- | --- |
| the lit primary action | `set_gradient` + `set_glow` + `CornerStyle.Pill` |
| the selected rail entry | the same three, on a row |
| a tag | `CornerStyle.Pill` |
| an icon tile | `set_gradient` + `set_image` on **one** widget |
| a card's photo head | `set_image` on the plate panel |
| the hero's copy over its picture | children of the panel that holds the image |
| the page ground | `set_gradient` on the root |
| the glass rail | an alpha below 255 |
| a tab's underline | a two-point panel, which the corner policy reads as a bar without being told |

None of that is faked with a second colour and a hand-placed rectangle. Before
this stretch of work, most of it could not be said at all.

## What building it found

**A child of something that cannot hold children was silently a root.** Only a
panel and a scroll viewport nest. Asking a button for a child used to hand back
a perfectly valid widget that was secretly a root — laid out across the whole
viewport, painted over everything, taking the pointer anywhere it was
transparent. Every icon tile in this rail was a full-window pane, and the frame
looked *almost* right the entire time. Builders refuse it now, with the same
sentinel a full arena returns.

**A button does not measure its caption.** A minimum is declared once, at
construction; a label remeasures from its text on every layout pass. Tabs asked
for zero width came out zero wide and the whole tab row vanished into the
header. Nothing is wrong with either rule — but they are different rules, and
the example is where that stops being a footnote.

**Grow distributes the spare space, not the total.** Three cards whose minimums
differed by the width of their tags came out three different widths. Equal
columns need an equal base.

**A picture and the fill under it are often the same brightness by design.** The
fixture's "did the pictures arrive" check first sampled a card plate, where the
flat colour and the photograph were deliberately indistinguishable — so it would
have passed with no picture at all. It samples the hero's sky instead, which is
the one place in the frame where a picture and its fill are nothing like each
other.
