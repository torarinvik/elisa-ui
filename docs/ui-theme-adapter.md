# UiTheme and retained widget styling

`UiTheme` owns appearance facts and accessibility policy. It normalizes the
host's mode, contrast, text scale, and reduced-motion preference, then resolves
one complete `UiTheme::Palette` in Elisa. It does not know about widget storage
or native controls.

`UiFlat` and `UiHandles` expose a narrow adapter for applying that palette to a
retained tree:

```elisa
preferences: UiTheme::Preferences = UiTheme::current_preferences()
changed: bool = UiHandles::apply_system_theme(preferences, system_dark, system_high_contrast)
```

The adapter changes only framework-wide visual tokens:

- focus ring and selection colors;
- checkbox/radio control marks;
- scrollbar track, thumb, hover, and active colors;
- focus inset, text padding, slider track height, choice spacing, and choice
  marker metrics.

Per-widget surfaces, hover/press colors, text colors, and declared widget frames
remain application-owned. Applications that need a custom token can still copy
`UiFlat::theme()`, change the desired field, and call `UiHandles::set_theme()`.

`apply_palette` and `apply_system_theme` return `true` only when the normalized
framework theme changes. The underlying `set_theme` operation compares every
token after normalization, so repeated host appearance refreshes do not create
spurious layout, paint, or semantic invalidations.

Text scaling remains explicit through `UiTheme::scaled_text_size` and the
shared geometry resolver; this keeps
intentional per-control typography intact instead of silently rewriting every
retained widget. Reduced-motion timing is likewise queried with
`UiTheme::animation_interval` so an application can preserve a custom cadence
while disabling recurring animation when requested.

The adapter is pure Elisa and has no dependency on AppKit, SDL, Skia, or a
window. `test/widget_theme_adapter_test.elisa` exercises it headlessly,
including palette mapping, idempotence, custom-token preservation, and the
typed handle surface.
