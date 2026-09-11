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

## A hovered and a pressed frame, and grain

Every frame of the storefront was of controls at rest. The host now puts the
pointer on the primary action and holds it down, rendering one frame per
motion step so the first is *mid-transition* (`-hovering.png`, `-pressing.png`)
and a later one is settled (`-hover.png`, `-pressed.png`). The settled frames
must differ from rest and from each other, or the pointer reached nothing —
which it did on the first try, because the primary's hover colour *was* its
rest colour. A control whose hover is its rest is a control the pointer does
nothing to.

`PictureFit.Tile` repeats a picture at its own size across a box. The page
carries a 64-pixel tile of blue-tinted noise at 14/255: a mathematically smooth
ramp reads as vector, and this is what makes a background read as a surface.

## The same pictures through CoreGraphics

The Skia fixture is handed its pictures by a C++ host that synthesises them
pixel by pixel. An AppKit window and an iOS app have no host, so
`examples/storefront/pictures_cg.elisa` draws the same scenes with the
painter's own primitives — a ramp for the sky, a radial bloom for the sun, two
sine ridgelines, an even-odd ring for the mark, a field of one-point rects for
the grain — into bitmap contexts that become `CGImage`s. It declares no
CoreGraphics entry of its own beyond what both backends already call, and the
painters expose one door, `bind_picture(slot, generation, image)`, through
which an entry point hands a picture over by the two numbers a command carries.
The pictures are made before the backend has a surface; `StoreApp::set_pictures`
keeps them until the tree exists and applies them then.

## The phone form

The composition was built at tablet width, and at phone width it crushed the
grid and ran the tabs into the title. The form is chosen once, when the tree is
built, from the width the surface reported (under 700 points): the rail keeps
its marks and hides its captions, section names, brand line and promo; the
top row keeps the search and the account capsule; the tabs take a row of their
own under the title and the create action becomes a `+`; the hero tightens its
copy; the cards run in one column; and the page sits in a scroll viewport,
which a finger pans. Everything hidden is still built, so the tree is the same
at either width and only its cloth changes. Rotating a phone after launch does
not re-form the page — the form is a construction decision, not a layout one.
