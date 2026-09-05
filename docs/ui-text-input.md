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
