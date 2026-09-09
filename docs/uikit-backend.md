# The UIKit backend

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
* **No composition, and it says so.** The view adopts `UIKeyInput`, which
  commits finished text and has no marked-text phase, so the profile reports
  `composition: false`. Adopting the full `UITextInput` protocol is what would
  change that; until then an application asking
  `UiCapabilities::supports_composition` gets the truth.

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

`test/uikit_input_test.elisa` and `test/uikit_surface_test.elisa` pin the input
mapping, the surface facts, the semantic mapping, and a genuine off-screen frame
with its semantic transaction.
