# Shared appearance and accessibility preferences

`UiTheme` is the backend-neutral policy for appearance facts that otherwise
drift between native and custom painters. A host supplies system facts; Elisa
normalizes them and resolves one palette:

```text
palette = UiTheme::resolve(preferences, system_dark, system_high_contrast)
```

The resolver covers light/dark/system appearance, normal/high contrast, and a
bounded text scale (`0.5..3.0`). `scaled_text_size` additionally caps the final
extent so malformed or huge application values cannot poison layout. The
`reduced_motion` preference maps animation intervals to the framework's zero
sentinel, which disables recurring caret/frame animation without changing
ordinary geometry.

Applications that change appearance at runtime can use `set_preferences`. It
stores one normalized preference record in a bounded Elisa-side state, exposes
an idempotent monotonic `revision` and `snapshot`, and invalidates layout,
paint, and semantics together. Repeating the same normalized values is a no-op;
malformed enum or scale values are canonicalized before comparison.

The module is opt-in: applications that do not need shared palette policy do
not pay for its resolver in their handle-heavy binaries. Applications may
override any resolved token through their stable theme API after resolution.

`UiTheme::metrics` resolves shared geometry tokens for spacing, minimum touch
targets, focus-ring width, and corner radius. High-contrast mode raises touch
and focus affordances and adjusts spacing consistently across controls.
`UiTheme::scaled_metrics` applies the normalized text scale to spacing and touch
targets with the same finite extent cap used by text sizing.
