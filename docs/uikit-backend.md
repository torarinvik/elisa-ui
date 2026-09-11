# The UIKit backends

iOS has two, mirroring macOS: a custom-painted canvas (this document) and a
native-controls backend
([`ui_uikit_controls.elisa`](../src/platform/uikit/ui_uikit_controls.elisa))
that owns no pixels and realizes the portable widget tree as real UILabels,
UIButtons, UISliders and UITextFields through the same `UiControls` protocol the
AppKit controls backend implements. An application links exactly one; both build
with `scripts/build_uikit.sh <example> <simulator|device> <canvas|controls>`.

Two decisions in the controls backend are worth stating, because iOS has no
exact counterpart for them. A `Window` becomes an ordinary container view: the
scene owns the only real window, so inventing a second `UIWindow` the platform
would never show would be worse than keeping the hierarchy as given. And a
`CheckBox` becomes a selectable `UIButton` rather than a `UISwitch` — a switch
is the iOS control for a bare boolean, but it carries no caption, and a
selectable button keeps the widget's own text visible, which is the same control
iOS uses for check and radio rows.

Three more, found by building a tree with every control kind in it and looking
at the result on a phone.

**A child is placed inside its parent.** `UiWidgets::layout` computes absolute
boxes and every toolkit this seam targets — `NSView`, `UIView`, a child `HWND`,
`GtkFixed` — takes a child's frame in its *parent's* coordinates. Handing the
absolute box straight to the setter is right for one level and wrong by the
parent's origin for every level after it, compounding down the tree. A toolbar
at the origin looked perfect and hid it; the moment anything was nested two deep
it walked off the bottom of the screen. `UiControls::placed_box_at` now does the
subtraction once, for every backend, and the root — which has no parent to sit
inside — keeps its own box.

**Colour reaches the controls that can show it.** The protocol carried captions,
state and frames but no colour at all, and a fresh `UILabel`'s `textColor` is
*black*, not the semantic label colour — so on a dark scene every label in the
interface was invisible, and every panel's fill was missing. `set_colors` is now
part of the protocol and `UiControls::palette_of` decides what crosses: a label's
ink, a panel's fill, a text field's both, and a slider's or gauge's bar and track.
A **button's** rest/hover/press do not cross, because they are the framework's
answer for a surface it paints itself and iOS draws a better one. Alpha zero is
the hierarchy saying nothing, which is what leaves an unstyled control looking
exactly like the platform drew it — because the platform did.

**Realizing twice replaces the interface.** The scene calls
`app_controls_realize` again whenever its geometry changes — a rotation, a split
view — and releasing the bridge's retain does not take the old tree off the
screen, because the scene's own view is still holding it. Without detaching the
old root, a rotation left two complete interfaces stacked with the dead one on
top, taking the touches.

## Typing in a real UITextField

A native field is the strongest single reason to realize native controls: it
brings the IME, autocorrect, dictation, the selection magnifier and the system
paste menu, none of which a framework that draws its own caret can borrow. All
of that is worth nothing if the words never reach the application, and for a
while they did not — the action carried a float and a flag, and a string had
nowhere to ride.

It now has a channel of its own, `elisa_uikit_controls_text_action`. The shim's
one target reports a `UITextField` through it rather than through the numeric
path, because what `UIControlEventEditingChanged` delivers is the string
UIKit's own editor produced — after the IME, autocorrect, dictation or a paste
have had their say — and not a keystroke. Elisa copies the bytes (they belong
to an autoreleased buffer valid only for the call) and hands them to
`UiControls::dispatch_native_text`, which writes them into the control list and
then into the retained widget through `UiFlat::replace_text` — the retained
layer's own editing entry point, not a second one written for native backends.
It validates the UTF-8, clips on a grapheme boundary, records an undo step and
emits the change event exactly once, which is why a field returns early instead
of also falling through to the shared action event.

**Focus has to outlive the interface.** Realizing again replaces every control,
which is how a tree that changed shows up — and it would also destroy the very
field that reported the keystroke, dropping the keyboard, losing the caret and
cutting a composing IME off mid-word. The realization remembers which *retained
widget* held focus, and its caret in UTF-16 units, then gives focus back to
whichever control realizes that widget. The identity is deliberately the widget
and not the control index: an index belongs to one realization, and a
validation message that appears when the text becomes invalid shifts every
index after it, while the widget is what the application itself holds.

UIKit publishes no first responder to walk to, so Elisa asks each control it
owns — `elisa_uikit_controls_is_focused` — rather than the shim walking a view
tree it does not own the table for.

`test/controls_flat_test.elisa` pins all of this with a recording backend and no
OS control in sight: that the text arrives, that one keystroke is one edit,
that an unchanged report raises nothing (which is what stops a backend that
re-realizes on every event from chasing its own tail), that clearing a field is
a real edit, and that a label refuses a write-back it should never receive.

## Realizing again keeps what did not change

Realizing used to mean destroying every control and building a new one. For a
rotation — the only moment a realization used to happen — that cost nothing
anybody could see. Then a field started reporting what the user typed, and an
application that lays out again when its text changes turned every keystroke
into a full teardown of the control being typed into.

So a realization now reconciles. The previous list is moved aside, the new one
is built beside it, and a control is **adopted** — its native object carried
over untouched — when nothing a toolkit would have to rebuild for has changed.
What counts as unchanged is deliberately narrow: **same position in the list,
same kind, same parent**. Not the frame, the colours, the text or the state —
those are applied to an adopted control exactly as to a new one. It is the
identity that has to match, and position-plus-kind is the identity a list
without keys can offer; a tree that changes shape gets the old behaviour for
the part that shifted, which is never wrong, only slower.

**A child is only adopted if its parent was.** Every toolkit here holds a child
inside its parent, so a rebuilt parent has no children, and an adopted child
would be a live native object attached to a view being released. The list is
parent-first, so one pass carries that rule down a subtree.

Two things fell out of this that are worth stating, because both were bugs
before they were rules:

- **A control answering a change the framework just made is not the user.**
  Setting a toggle's selection or a slider's value makes a toolkit call the
  action it was given — `setChecked` fires `onCheckedChanged`, a `UIControl`
  sends its target — so the write-back arrives as if a finger had done it.
  Ordering used to cover this: a fresh control is given its action last, after
  its state. An adopted control still carries the action it was given the first
  time, so the guard moved into the seam: `apply` refuses reports while it is
  writing.
- **A setter is skipped only when it would write what the control already
  holds**, and that needs a record of what each control was actually *given*.
  Comparing against the control list instead is a different thing and it is
  wrong: `note_selection` turns a radio's siblings off in the list without
  telling those controls, so the list already agreed, the un-check was skipped,
  and both tabs read as selected in Android's own view dump. The record is
  written where the applying happens, and by the `note_` functions — a control
  that *reported* a value is holding it already, which is exactly why a field
  is never handed back its own edit. `setText` on the field being typed in puts
  its caret back to the start.

Skipping is only safe when the value matches; "probably harmless" is not the
same test. Colours were skipped for adopted controls on that reasoning, and the
showcase's validation message said "Email looks good." in red.

Measured on a Pixel 9: typing into a native field now creates and releases
nothing, and the five characters of "Grace" arrive as five.

## The other application layer

elisa-ui has two application-facing layers and until now they were not equally
served. **Every application in this repository is written against
`UiHandles`** — the retained tree — and that tree can be painted by Skia, by
either CoreGraphics canvas, by SDL3 and by the browser. It could not be
realized as native controls at all, because the controls seam consumed the
*other* layer: the immediate `UiWidgets` hierarchy. The native backends were
not missing features so much as missing their applications.

`UiControls::realize_retained` walks the retained arena and fills the same
control list the hierarchy walk fills. There is no second protocol and no
second list; a backend cannot tell which layer a control came from.
`examples/showcase/uikit_controls_main.elisa` is the showcase — the same five
pages the Skia build paints — as UILabels, UIButtons, UISliders and
UITextFields, and nothing under `examples/showcase` changed to allow it.

**What does not cross, and why that is not a hole.** A retained widget carries
a ramp, a glow, a corner style, a picture, a halo and a surface depth. A native
control has no place for any of them, because it has the platform's own — which
is the entire reason to realize one. The rule the hierarchy walk already
applied to a button's rest/hover/press applies to all of it: what a toolkit
draws for itself stops at the seam, and what is *content* — the words, the
value, the selection, the colour of text and of the surfaces behind it —
crosses. A hidden widget is not a control either: the retained layer keeps all
five showcase pages in the tree and shows one, and realizing the other four
would hand iOS four interfaces to stack.

**A control's action lands on the widget it came from.** The seam already
records a new value into the list before the application sees the event;
`retained_action` carries it the last step, into the retained widget, and then
calls the application's own `app_widget_event` — the same hook every canvas
backend calls. The application changes its tree in response, and the entry
point lays it out and realizes it again. That is the whole loop: the one a
painted backend runs, with a realize where the paint would be. A field's
**text** does not come back this way — an action carries a float and a flag,
and a string has nowhere to ride — so a native field on this path edits itself
and the retained value does not yet follow it.

**The two layers cannot share a translation unit.** This is not a design
preference: the compiler declines a unit holding both layers' tree walks. So
the seam knows neither of them, `ui_controls_hierarchy.elisa` and
`ui_controls_flat.elisa` each know one, and a program includes the one it uses
— `ui_uikit_controls_hierarchy.elisa` or `ui_uikit_controls_flat.elisa`. The
same split found a name clash that had been invisible: `UiControls::Kind` is
now `ControlKind`, because three other modules in the widget layer declare a
`Kind` and every record that carries one calls the field `kind`, which stage1
declines where two such names meet.

`examples/hello/uikit_controls_main.elisa` is the tree that found all three: it
builds one of every kind the backend realizes, on purpose, because a vocabulary
with a hole in it looks exactly like one without until somebody builds the
widget that falls in it.

# The UIKit canvas backend

elisa-ui runs on iOS through the same architecture as the macOS canvas: Elisa
owns the retained widget tree and emits a batch of `UiCore::Command` values, and
the platform replays that batch. On both Apple platforms the replay is
CoreGraphics and the text is CoreText, so the pixels come from the same code
paths; what differs is the host, the pointer, and the shape of the surface.

## What the platform owns, and what it does not

`src/platform/uikit/uikit_shim.m` is one translation unit, split into fragments
under `shim/`. It creates the application, the window, the root view controller,
the view and the accessibility elements, and it forwards raw facts: a touch
phase and location, a USB HID usage and a modifier bitfield, a safe-area inset,
a keyboard frame, a notification name.

Every decision that follows from those facts is in Elisa:

| Fact from UIKit | Decided in |
| --- | --- |
| `UITouchPhase`, location, tap count | `ui_uikit_input.elisa` — which framework event a phase produces, and that a press must synthesize the move a mouse would have delivered first |
| `UIKey.keyCode` (HID usage), `modifierFlags` | `ui_uikit_input.elisa` — the key, the editing chord, and whether a press goes to the text system |
| Safe area, keyboard frame, size, scale | `ui_uikit_surface.elisa` over `UiMobileSurface` — validation, insets, orientation, and the logical viewport |
| Semantic role | `ui_uikit_accessibility.elisa` — `UIAccessibilityTraits`, and the value string VoiceOver speaks |
| Element identity and reuse | `ui_uikit_semantics.elisa` — the shim is told whether an element is new; it never probes a handle |
| When the assistive cursor should move | `ui_uikit_semantics.elisa` — a fresh tree is a *screen* change; a moved retained focus moves VoiceOver; an ordinary repaint moves nothing |
| Application notifications | `ui_uikit_callbacks.elisa` — one lifecycle vocabulary shared with every other backend |

`scripts/check_uikit.sh` enforces that split as "must not contain" checks over
the shim sources, the same way the AppKit canvas gate does.

## Differences from the macOS canvas

* **The lifecycle starts later.** `UIApplicationMain` owns the process, so
  `UiUIKit::run` prepares the session and enters UIKit; the surface arrives
  afterwards, in `viewDidLayoutSubviews`. `UiUIKit::attach_surface` is where the
  application's `app_init` runs. `UiMobileSurface` owns the Begin/Ready
  transition that comes with acquiring a surface, so a started session is
  renderable but not yet focused — UIKit reports focus separately.
* **There is no hover.** A touch begins with a press, so the adapter emits the
  move first; without it a control never sees the pointer arrive and cannot show
  its pressed state. A cancelled touch releases the pointer *without*
  activating, which is why `Cancelled` is not folded into `Ended`.
* **The keyboard is an inset, not a smaller surface.** It arrives through
  `UiResponsive::KeyboardInsets` so a form can scroll its focused field into the
  remaining content area.
* **The software keyboard follows focus.** UIKit raises it for a first responder
  that reports it accepts text, so the adapter asks for and resigns first
  responder as the retained focus changes.
* **Scale changes.** `UiCapabilities::use_uikit` reports `scale_changes`,
  because a device rotates and can move between displays.
* **Composition goes through `UITextInput`.** UIKit expresses text in opaque
  `UITextPosition` and `UITextRange` objects; here they are UTF-16 offsets into
  the focused field, so the shim's implementations are thin integer wrappers and
  every question that needs the text — document length, whether an offset
  exists, what a clamped range covers, where a caret sits, which offset a touch
  lands on — is asked of Elisa
  (`ui_uikit_flat_text.elisa`). A marked range from a Japanese keyboard, from
  dictation or from autocorrect reaches `UiFlat` through the same
  `update_marked_text`/`unmark_text` pair the AppKit adapter uses. A secure
  field still refuses readback, through the same
  `UiFlat::allows_text_readback` gate as the clipboard.

## System appearance

`ui_uikit_appearance.elisa` records three facts UIKit reports — interface style,
accessibility contrast, and Dynamic Type — and repaints when one of them
actually changed (UIKit posts a trait change for every trait, including ones
this backend does not read). Nothing is applied: a palette is application
state. An app that wants to follow the system reads
`UiUIKit::system_preferences` and hands it to `UiTheme::resolve`.

Dynamic Type arrives as the scaled size of the body text style rather than a
category name, so Apple's category vocabulary never has to be mirrored in the
shim; Elisa divides by the unscaled body size to recover a plain multiplier and
bounds it.

## The edit menu

UIKit asks a responder which standard editing actions it can perform and then
sends the matching selector. Both questions are forwarded as the opaque `SEL`:
Elisa decodes it through `sel_getName`, maps the runtime spelling onto the same
action vocabulary the AppKit adapter uses, and answers enabled-ness from the
retained text state. The shim holds no action table and no enabled-ness rule.

## The iPad pointer

An iPad with a trackpad or mouse does have hover, and a pointer that changes
shape over a control — so the "there is no hover" rule above is about touch, not
about the platform. A `UIHoverGestureRecognizer` feeds the same `Move` event a
mouse would, and a `UIPointerInteraction` asks Elisa for the region under the
pointer: `uikit_flat_pointer_region` returns the control's own frame plus the
same cursor token the macOS canvas uses (0 default, 1 an activating control,
2 text). The frame is what lets iPadOS morph the pointer into the control; a
miss reports no region, so UIKit keeps its own default rather than snapping to a
rectangle the framework did not choose.

Indirect scrolling arrives at a `UIPanGestureRecognizer` restricted to the
indirect pointer. A finger has a pan recognizer of its own, with the same
handler and the same Elisa entry: UIKit decides when a touch has become a drag,
cancels the forwarded touches when it does — the pressed control releases
without activating — and every update from then on is a scroll delta to
whatever viewport is under it. A tap stays a tap; a drag scrolls; the widgets
see one event for a finger, a wheel and a trackpad.

## Building and testing

```bash
scripts/build_uikit.sh hello simulator   # a .app for the iOS Simulator
scripts/build_uikit.sh hello device      # a .app for a device (ad-hoc signed)
scripts/check_uikit.sh                   # the full gate
```

The build cross-compiles everything for the requested triple, including the
runtime object — the host runtime is a macOS image and cannot be linked into an
iOS one. The link runs through the compiler's own `-emit exe` path with
`ELISA_CLANG` pointed at a wrapper that adds the SDK, the triple and the
frameworks, so the weak callback fallbacks the runtime expects come from the
compiler that defines them rather than a copy here that would drift.

The gate has two halves, neither of which needs a booted simulator:

1. It builds and links the whole product for the simulator and for a device. A
   successful link is the strongest available proof that the two halves of the
   backend agree on their shared ABI, and it is checked in both directions —
   the backend must not export a callback no shim fragment calls.
2. Everything below the shim is ordinary Apple platform code, so it is built and
   *run* on the host against C stand-ins for the shim's entry points
   (`test/uikit_host_stubs.c`), including one real off-screen frame written out
   as a PNG and required to be byte-identical across fresh processes.

### And then actually running them

`scripts/check_uikit_simulator.sh` boots a simulator and runs both backends on
it. The two halves above are about what the framework decides and whether the
products link; this is about whether a real iOS delivers the facts those
decisions are made from. `examples/uikit_smoke` prints one line whenever a
reported fact changes, so the gate reads what reached Elisa instead of inferring
it from pixels: the scene's own width and display scale (not a size compiled
into the app), safe-area insets that are actually non-zero, a real dark-mode
trait change, a real Dynamic Type change, and the Active/Inactive transitions
that come from genuinely backgrounding the app. Then it launches both `hello`
products and checks each painted something.

It skips itself when no iOS runtime is installed; install one with
`xcodebuild -downloadPlatform iOS`.

### A real touch

`simctl` cannot inject a touch, so `scripts/check_uikit_touch.sh` drives
`XCUIApplication`, whose taps go through the simulator's own HID pipeline — the
same path a finger takes. One test covers the whole chain, because each link is
required for the next to be observable:

* XCUI can only see a custom-painted canvas through its accessibility elements,
  so finding the button at all proves the semantic tree reached iOS;
* the tap proves UIKit delivered the touch to the view and the framework routed
  it into the retained model;
* the status text the application rewrote coming back out proves the callback
  ran, the frame repainted, and the new semantics were published;
* a second tap reporting a different text proves the framework did not latch.

There is no Xcode project here, so the script assembles the runner by hand from
the `XCTRunner.app` template Xcode ships — embedding the test frameworks and
writing an `.xctestrun` — which is all an Xcode scheme would otherwise do.

This is also why the semantic tree is published unconditionally rather than only
when VoiceOver is running: assistive technology is not its only reader. Voice
Control, Full Keyboard Access, the accessibility inspector and UI automation all
consume it, and several have no public "is running" flag to gate on.

`test/uikit_input_test.elisa`, `test/uikit_surface_test.elisa` and
`test/uikit_text_input_test.elisa` pin the input mapping, the surface facts, the
semantic mapping, a genuine off-screen frame with its semantic transaction, and
the text protocol — offsets and their sentinel, range bounding, selection,
composition, caret and range geometry, touch-to-caret, and a secure field's
refusal to hand its text back.
