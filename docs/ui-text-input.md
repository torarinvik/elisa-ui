# Text-input policy

`UiTextInput` resolves a field's purpose into backend-neutral traits. Plain,
email, URL, number, search, and password fields select keyboard hints and
multiline behavior in Elisa; native/hosted adapters only apply those traits to
their text bridge.

Password traits are hardened regardless of caller options: secure entry is
enabled, multiline/autocorrect/suggestions are disabled, and clipboard plus
semantic value readback are denied. Number fields accept digits and common sign
or decimal characters while leaving locale-specific formatting to the host;
other purposes continue to accept composed Unicode input and IME commits.

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
