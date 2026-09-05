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

The module is opt-in: applications that do not need shared palette policy do
not pay for its resolver in their handle-heavy binaries. Applications may
override any resolved token through their stable theme API after resolution.
