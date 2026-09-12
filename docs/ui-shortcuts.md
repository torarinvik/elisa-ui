# Shortcut precedence

`UiShortcuts` ([src/widgets/ui_shortcuts.elisa](../src/widgets/ui_shortcuts.elisa))
answers one question for every backend and for headless tests: which layer owns
a key press? The precedence, from highest to lowest, is:

1. **OS-reserved actions** (`Reserved`). Registered with `reserve_os`, they are
   reported but never consumed, so the native or host action still fires.
2. **Focused editable control** (`FocusedControl`). When the focused control
   accepts text, it gets first refusal before any application accelerator, so
   typing and caret navigation are never stolen.
3. **Application command bindings** (`ApplicationCommand`).
4. **Menu accelerators** (`Menu`).
5. **Unhandled**, which the application may treat as data.

`resolve(key, modifiers, focused_editable, is_repeat)` returns a `Decision`
with the winning `Layer`, the bound command id for the command/menu layers, and
whether the framework consumed the key.

Modifiers are matched exactly: a binding for Control+S does not fire for
Control+Shift+S unless that binding is registered too. A binding may opt out of
key repeat (`allow_repeat = false`), so a held-key action is explicit.
Re-registering the same `(key, modifiers, layer)` is idempotent, which keeps a
view rebuild from accumulating shadow bindings.

The `UiFlat` keyboard router already implements layer 2 for the controls it
owns; applications and platform adapters use this resolver so their command and
menu layers cannot drift from it. The registry is bounded and opt-in, so a
small app pays nothing for a precedence table it does not use.

`test/shortcuts_test.elisa` covers the ordering, exact modifier matching, key
repeat, idempotent registration, invalid input, and reset.
