# Text-input policy

`UiTextInput` resolves a field's purpose into backend-neutral traits. Plain,
email, URL, number, search, and password fields select keyboard hints and
multiline behavior in Elisa; native/hosted adapters only apply those traits to
their text bridge.

Password traits are hardened regardless of caller options: secure entry is
enabled, multiline/autocorrect/suggestions are disabled, and clipboard plus
semantic value readback are denied. Secure text remains available through the
control's app-facing value API, but it is never exported as selected text or a
semantic value and never enters text undo/redo history. Enabling secure mode on
an existing field scrubs the shared undo/redo ring, including edits to other
fields; subsequent edits to the secure field remain undo-ineligible. Secure
values are also rejected by the typed application-state persistence adapter.
Tree reset scrubs the retained text, secure storage, clipboard staging, and
history buffers. Number fields accept digits and common sign or decimal
characters while leaving locale-specific formatting to the host; other
purposes continue to accept composed Unicode input and IME commits.

Range units are explicit at the boundaries. The retained editor stores
selection and marked positions as UTF-8 byte offsets; `UiFlat::set_selection`
and the legacy `UiHandles::set_selection` accept those byte offsets and floor
them to extended-grapheme boundaries. `UiHandles::set_selection_utf16` accepts
UTF-16 code units, as do the selection/marked getters and the AppKit/UIKit text
protocol adapters. SDL3 and the C callback contract express IME composition
ranges as UTF-8 scalar counts, not bytes; those adapters bound the scalar range
before mapping it into the retained editor. UTF-16 offsets inside a surrogate
pair resolve to the scalar's leading boundary, then selection setters apply the
grapheme boundary rule. `UiFlat::text_range_location` and `text_range_length`
use UTF-16 units; `text_range_pointer` and `text_range_byte_length` address the
corresponding UTF-8 storage. These units must not be interchanged.

The retained `TextField` is single-line. Committed, programmatic, and clipboard
insertions normalize control and Unicode line-separator bytes to spaces;
`widget_layout_text_test` pins multiline clipboard paste to the normal insert
path.

Word-wise caret movement and deletion are reachable from the keyboard on every
backend that routes through the flat keyboard handler (SDL3, WasmBrowser,
UIKit): Alt/Option or Control with Left/Right moves by word, Shift extends the
selection, and Alt/Option or Control with Backspace/Delete removes a word.
Alt/Option is tracked as an independent modifier so macOS and desktop
Linux/Windows conventions both work. The AppKit canvas reaches the same shared
helpers through its menu selectors, so both input paths agree.
`test/word_navigation_test.elisa` covers the routing and the grapheme-safe word
boundaries.

Known hosted limitation: the current `wasmbrowser:window/guest@0.1.0`
`key-code` enum has `shift` and `control` but no `alt`, so Control+Left/Right
and Control+Backspace/Delete work in the hosted backend while Option/Alt does
not. Adding `alt` is a WasmBrowser WIT change (WB-05), not a local override;
until then the hosted adapter uses the Control convention.
