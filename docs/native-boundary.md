# Native boundary audit

The AppKit implementation is intentionally split between Elisa policy and a
thin Objective-C FFI surface. The remaining native code was reviewed after the
event-queue and button-toggle migrations; each category below requires an OS
object, an Objective-C protocol callback, or an ABI-level fact.

| Native surface | Why it remains native |
| --- | --- |
| `NSWindow`, `NSView`, `NSPanel`, `NSScrollView`, and control construction | Cocoa allocators and initializers return Objective-C objects and own their native behavior. The custom canvas constructor accepts only dimensions and ABI style/backing facts; Elisa assigns the framework-owned title through a separate typed setter after the handle exists. |
| `NSView`/`NSWindow` attachment, frame writes, presentation, activation, close, and run-loop calls | These operations message live AppKit objects; Elisa supplies all dimensions and policy values. |
| `ElisaCanvasView` and `ElisaCanvasDelegate` protocol methods | AppKit requires Objective-C method dispatch for drawing, pointer/key/text-input, focus, resize, tracking, and close notifications. Methods forward raw facts into Elisa. |
| `NSTextInputClient` range/coordinate conversion | `NSRange`, screen/window/view conversion, and `interpretKeyEvents:` are Cocoa protocol ABI shapes. Range meaning and editing policy are resolved in Elisa. |
| `NSAccessibilityElement` subclass/property mirroring | VoiceOver requires Objective-C accessibility objects and protocol setters. Stable IDs, identity reuse, roles, values, actions, and notification policy live in Elisa. |
| CoreFoundation/CoreGraphics/CoreText/ImageIO calls | These are system object handles and drawing/rasterization ABIs; command generation, clipping, text policy, and snapshot sequencing remain in Elisa. |
| Optional `appkit_skia_host.cpp` compositor | The host receives a borrowed CGContext, validates/rounds backing extents, creates a temporary Skia surface, and copies pixels back for AppKit presentation. Elisa still prepares/replays the frame, selects the aspect-preserving backing scale, and owns renderer selection; the bridge is linked only by the Skia custom-canvas product. |
| Pasteboard, cursor, timer, menu, and selector object calls | The OS owns service authority and object lifetimes. Elisa chooses text, menu schema, selector/action mapping, timing, and cursor rectangles. Redraw timer delivery re-enters Elisa with an opaque window handle, where lifecycle and stale-window checks decide whether to request a frame; the native block does not capture an `NSView`. |
| Native introspection (`isKindOfClass`, frames, styles, scroller state) | Tests need facts read from live Cocoa objects. The shim does not retain a parallel widget table or perform framework policy. |

No native branch currently owns retained widget state, layout traversal, paint
commands, event translation, text editing, semantic identity, menu schema,
clipboard policy, lifecycle interpretation, capability selection, or event
queue/backpressure. Those decisions are implemented and tested in Elisa.

UIKit semantic output uses `elisaPublishValue:` to update the native
accessibility object's value without invoking its assistive-edit override.
Only genuine `setAccessibilityValue:` requests enter retained editing. This
directional separation prevents semantic frame publication from collapsing
selection or cancelling composition. The UIKit edit-menu fragment constructs
native menu objects from Elisa's schema, validates document ownership/action
eligibility through Elisa, and forwards selectors to the retained editor.

UIKit's `UITextSelectionDisplayInteraction` supplies native selection handles;
Elisa continues painting the themed caret and range highlight. A canvas pan
recognizer forwards the handle endpoint and raw position. Elisa owns the fixed
opposite endpoint, UTF-16/grapheme normalization, cancellation restoration and
tree/field/revision validation. Handle contacts suppress the compatibility
pointer stream so a canvas press cannot collapse the range being adjusted.
Elisa's mobile interruption stamp retires captured drags across focus,
background and surface-loss round trips even without an intervening callback.
The lifecycle adapter also requests immediate native presentation suspension:
the shim dismisses menu objects, deactivates the selection display and toggles
the native handle pan off/on to cancel it. It does not decide lifecycle policy,
clear retained selection or resign the editor.
