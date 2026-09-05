# Native boundary audit

The AppKit implementation is intentionally split between Elisa policy and a
thin Objective-C FFI surface. The remaining native code was reviewed after the
event-queue and button-toggle migrations; each category below requires an OS
object, an Objective-C protocol callback, or an ABI-level fact.

| Native surface | Why it remains native |
| --- | --- |
| `NSWindow`, `NSView`, `NSPanel`, `NSScrollView`, and control construction | Cocoa allocators and initializers return Objective-C objects and own their native behavior. |
| `NSView`/`NSWindow` attachment, frame writes, presentation, activation, close, and run-loop calls | These operations message live AppKit objects; Elisa supplies all dimensions and policy values. |
| `ElisaCanvasView` and `ElisaCanvasDelegate` protocol methods | AppKit requires Objective-C method dispatch for drawing, pointer/key/text-input, focus, resize, tracking, and close notifications. Methods forward raw facts into Elisa. |
| `NSTextInputClient` range/coordinate conversion | `NSRange`, screen/window/view conversion, and `interpretKeyEvents:` are Cocoa protocol ABI shapes. Range meaning and editing policy are resolved in Elisa. |
| `NSAccessibilityElement` subclass/property mirroring | VoiceOver requires Objective-C accessibility objects and protocol setters. Stable IDs, identity reuse, roles, values, actions, and notification policy live in Elisa. |
| CoreFoundation/CoreGraphics/CoreText/ImageIO calls | These are system object handles and drawing/rasterization ABIs; command generation, clipping, text policy, and snapshot sequencing remain in Elisa. |
| Pasteboard, cursor, timer, menu, and selector object calls | The OS owns service authority and object lifetimes. Elisa chooses text, menu schema, selector/action mapping, timing, and cursor rectangles. |
| Native introspection (`isKindOfClass`, frames, styles, scroller state) | Tests need facts read from live Cocoa objects. The shim does not retain a parallel widget table or perform framework policy. |

No native branch currently owns retained widget state, layout traversal, paint
commands, event translation, text editing, semantic identity, menu schema,
clipboard policy, lifecycle interpretation, capability selection, or event
queue/backpressure. Those decisions are implemented and tested in Elisa.
