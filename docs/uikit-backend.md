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
indirect pointer, so it cannot compete with finger touches.

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
