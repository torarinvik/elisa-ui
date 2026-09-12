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
