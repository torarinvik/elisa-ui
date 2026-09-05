# Custom-painted AppKit backend

This backend gives AppKit ownership of the macOS window, event queue, graphics
context, pasteboard and accessibility objects while Elisa lays out, draws and
operates every control. It uses `UiCore::Command` values rather than native
`NSControl` instances.

The Objective-C file is intentionally a thin FFI shim. It forwards raw pointer
and keyboard facts, exposes the active graphics context, implements the methods
required by `NSTextInputClient`, and owns objects that only Cocoa can create.
Elisa calls CoreGraphics' C ABI directly for every path, including rounded
rectangles, circles, triangles, lines, the canvas clear, colors and shadows. It
also calls CoreText's C ABI directly for font metrics, shaping and text drawing.
AppKit key-code translation, visual styling decisions, UTF-8/UTF-16 conversion,
selection/replacement rules and IME composition state all live in Elisa. Elisa
also creates every outbound `CFString` and decodes inbound Cocoa strings with
CoreFoundation FFI; Objective-C only borrows those objects for Cocoa setters or
protocol callbacks.
Window minimums, cursor policy, bitmap extents and pixel format, frame-observed
headless validation,
accessibility adjustment steps, raster styling,
color normalization, rendering-quality options, accessibility interaction/value
kinds, the standard menu schema, shortcut and text-input routing, click-count
interpretation, and headless/snapshot configuration are also selected in Elisa;
the shim receives raw event facts and explicit values to apply.

## Minimal entry point

Include the flat adapter and the application implementation, then run the host:

```elisa
include "../../src/platform/appkit/ui_appkit_canvas_flat.elisa"
include "app.elisa"

def main() -> i64:
    return UiAppKitCanvas::run("My app", 800.0, 600.0)
```

The adapter supplies the native accessibility activation, slider adjustment and
window-deactivation callbacks required by `UiFlat`. An application supplies:

```elisa
def app_init() -> void
def app_event(event: UiCore::Event) -> void
def app_frame() -> void
def app_widget_event(widget: usize, event: i32) -> void
```

Build a retained tree in `app_init`, relayout it for `UiCore::Event.Resize`, pass
pointer and key events to `UiFlat`, and call `UiFlat::paint()` from `app_frame`.
The complete working version is
[examples/hello/app.elisa](../examples/hello/app.elisa).

## Flat widgets

- `panel` lays children out by row or column, with padding, spacing and grow
  weights.
- `scroll` reserves a fixed viewport while retaining the full measured child
  strip. `UiFlat::set_scroll_offset` clamps and relayouts it, wheel events route
  to the innermost viewport, and hit testing/semantics ignore children outside
  every ancestor viewport. Overflowing viewports draw a proportional,
  allocation-free scrollbar from `UiFlat::Theme::scrollbar_track` and
  `scrollbar_thumb`; clicking the track pages by one viewport and dragging the
  thumb updates the offset with Elisa-owned pointer capture.
- `label` measures and paints static text.
- `button`, `radio_button` and `check_box` support hover, press, disabled,
  selected and keyboard-focus states.
- `slider` stores a normalized `0.0...1.0` value and supports pointer capture,
  arrow keys and accessibility increment/decrement.
- `progress_bar` presents a normalized, noninteractive value.
- `text_field` stores bounded UTF-8 text; supports caret navigation, pointer and
  Shift-arrow and word-wise selection, selection-aware character/word deletion,
  double-click word selection, triple-click select-all, horizontal reveal and
  Shift-click extension, marked text, and a focused caret that blinks from a
  monotonic clock and restarts after navigation, selection or editing; receives
  Unicode through AppKit's text input manager; and maintains a
  bounded, allocation-free 32-step undo/redo history across fields. A complete
  IME composition is coalesced into one history entry. Character movement and
  deletion preserve combining sequences, variation selectors, emoji modifiers,
  regional-indicator flags and zero-width-joiner emoji as atomic clusters; the
  fixed-capacity storage boundary uses the same cluster rules. Public text APIs
  retain only a well-formed UTF-8 prefix, rejecting invalid, overlong, surrogate
  and out-of-range sequences before they reach a painter or native bridge.
  ASCII controls plus CR, LF, NEL and Unicode line/paragraph separators from
  paste or programmatic updates are normalized to spaces, preserving the
  control's single-line rendering contract. `text_was_truncated` reports
  whether the most recent input operation retained only a valid prefix because
  of malformed input or capacity exhaustion.
- `secure_text_field` uses the same editing engine while masking every painted
  and accessible user-perceived character, advertising AppKit's secure-text subrole, and
  disabling selected-text and native substring export so Copy/Cut and text
  queries cannot disclose the password. Reset and shortening edits explicitly
  scrub stale bytes from widget, display and undo-history buffers.

`UiConst::WidgetEvent.Click` reports discrete activation;
`UiConst::WidgetEvent.Change` reports slider and text changes, while
`UiConst::WidgetEvent.Submit` reports Return in a text field. Radio-group
exclusivity is application policy: set each member with
`UiFlat::set_selected` in the click handler.

`UiFlat::Theme` centralizes shared focus, selection and control-indicator colors
plus text, slider, choice-control and caret-timing metrics. Read the current value with
`UiFlat::theme`, modify a copy, then apply it with `UiFlat::set_theme`. Theme
state intentionally survives `UiFlat::reset`, allowing an application to
rebuild its widget tree without losing its visual system. Setting
`caret_blink_interval` to zero keeps the caret visible without scheduling
animation frames, supporting reduced-motion configurations.

Tab and Shift-Tab traverse enabled interactive controls. Enter and Space
activate discrete controls. Losing window focus cancels active pointer and key
state so a control cannot remain visually pressed. `UiCore::PointerButton.Primary`
(zero) is the portable primary button; other buttons neither activate controls nor disturb an
existing primary-button capture. AppKit forwards left, right and auxiliary
button presses, releases and drags with their native button identity; Elisa
alone decides that text multi-click selection is a primary-button operation.
Keyboard activation is similarly captured by
the original Enter or Space press; focus changes cancel it, unrelated key-up
events cannot complete it, and key repeat cannot transfer ownership.
Window focus gain and loss also arrive as portable `UiCore::Event` variants.
Applications using `UiFlat` pass those variants to `UiFlat::lifecycle`; focus
loss releases pointer/key capture and latched modifiers while preserving the
logical focused control for when the window becomes active again.
Focusing a descendant inside a flat scroll viewport automatically reveals the
smallest visible range, including through nested scroll ancestors.

## Accessibility

Each painted control produces a parallel semantic node containing its stable
identifier, role, label, optional help, frame, enabled/focused/selected state and
normalized value. Elisa owns the retained opaque handle for each live semantic
element and releases handles that leave the tree; the AppKit bridge reuses the
objects between frames, exposes actions to VoiceOver, updates screen-relative
frames after window moves, and applies the Cocoa role/subrole constants plus interaction,
tooltip and cursor tokens computed by Elisa from the same metadata. Value shape
(boolean, range, text, or empty) is selected in Elisa and sent through typed FFI
setters. Elisa also diffs semantic state between frames;
AppKit receives explicit value, focus, text-selection and layout notification
bits instead of inferring framework behavior from native objects. Text changes
use explicit widget edit revisions rather than per-frame string hashing.
Text fields expose writable values and native selection ranges to assistive
technology. Disabled controls expose no accessibility interaction token, so
native editing actions cannot claim or perform work. Press and adjustment
authorization is rechecked by `UiFlat`, and Cocoa returns that Elisa result
directly to assistive technology. Cocoa retains no framework interaction-kind
policy: accessibility edits carry their target widget id back to Elisa, and
tooltip eligibility arrives as an already-resolved boolean.
Each semantic text node carries its own selected substring; focus changes
cannot leave stale native selection content, and secure nodes always carry an
empty substring.

The canvas view implements AppKit's text-input client protocol. Cocoa forwards
native strings and UTF-16 ranges while Elisa performs the UTF-8 conversion,
selection/replacement rules and IME composition with an underline, positions the
system candidate window at the custom caret, and provides standard Cut, Copy,
Paste and Select All commands through both shortcuts and the Edit menu. Command
validation and execution are computed in Elisa from focus, selection,
secure-readback and undo-history state. Objective-C forwards Cocoa selector
names and raw modifier masks; Elisa maps them to opaque action tokens. The shim
exposes three byte-oriented pasteboard primitives; it never reads, deletes or replaces a
widget's selection itself. Elisa also decides when those mutations invalidate
the canvas; the native side only exposes the `setNeedsDisplay` primitive.
Key-release ownership follows the same rule: Cocoa forwards its hardware facts,
and Elisa decides whether the text-input system consumes them.

## Build and test without showing a window

```sh
scripts/build_appkit_canvas.sh
ELISA_UI_SMOKE_FRAMES=1 ./build/hello_appkit_canvas
ELISA_UI_SMOKE_FRAMES=1 \
  ELISA_UI_SNAPSHOT=/tmp/elisa-ui-frame.png \
  ./build/hello_appkit_canvas
```

Elisa selects the off-screen frame primitive directly in smoke mode and never
enters the native presentation or event-loop primitives. Objective-C retains
no headless-mode state. The off-screen primitive renders through a bitmap
`NSGraphicsContext`, verifies that AppKit actually invokes the frame callback,
and exits without showing or activating a window.
`scripts/check_appkit_canvas.sh` additionally checks callback symbols,
the application bundle, code signature, PNG dimensions and semantic-object
identity across redraws. `scripts/run_tests.sh` runs that check with the portable
unit suite.

Native window creation and presentation plus off-screen snapshot rendering
return status through FFI. Elisa owns the process result, chooses the visible
or headless sequence, and enters the native event loop only for a visible run.

The native-controls AppKit backend records each retained opaque Cocoa handle in
the same `UiControls` arena that owns its dense, capacity-checked index. Its
Objective-C half resolves those handles only at the FFI boundary; there is no
index→object table, native count or second platform-side limit to drift from the
retained control arena.

Animation scheduling is demand-driven. Elisa coalesces future-frame requests
and asks AppKit for a one-shot wake only while an animated element such as a
collapsed text caret needs it, leaving an idle window timer-free.

## Current boundary

The remaining Objective-C is the actual Cocoa boundary: `NSWindow`/`NSView`
and event-loop ownership, Objective-C selector identity/casting, `NSTextInputClient`
protocol/range plumbing, AppKit menus, pasteboard and accessibility objects,
bitmap snapshots and timers. These operations require Objective-C objects or
Cocoa protocol implementations; all UTF-8 conversion now lives in Elisa through
CoreFoundation FFI. Widget state, command policy, layout,
interaction, editing, accessibility diffing, headless orchestration, all
CoreGraphics path construction and CoreText text rendering now live in Elisa.
Menu action names are registered through the Objective-C runtime's C ABI from
Elisa; text-input selector names are decoded there as well. The shim receives
only opaque `SEL` tokens and forwards them across the FFI.

Elisa keeps one retained opaque handle to its root `NSWindow` for the duration of
each run. Every operation that needs the root window or canvas view receives
that handle explicitly through FFI; the Objective-C shim keeps no root lookup or
ownership slot of its own. This makes headless and visible runs use the same
explicit lifetime path, and releasing the handle after the run lets Cocoa tear
down the tree without a second native lifetime owner. The non-owning `NSWindow`
delegate follows the same pattern: Elisa retains and releases its opaque
delegate handle, while Cocoa only receives the protocol object. All window
policy and operations still cross the boundary as explicit FFI facts.

Text fields are currently single-line and deliberately bounded to 1023 UTF-8
bytes per widget so the flat layer remains allocation-free. Truncation preserves
UTF-8 and grapheme boundaries and is observable through `text_was_truncated`.
Multiline editing
is not yet part of this compact control; the separate native-controls AppKit
backend remains available when an application needs the complete native text
editor.
