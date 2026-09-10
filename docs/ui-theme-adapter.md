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

A choice marker is **typography**, and scales with the text preference. The
checkbox and radio sizes used to be derived from the focus ring's width — a
proxy for "high contrast wants them bigger" and nothing else — and the ring's
width is deliberately *not* scaled, because thickness is a style decision. So a
reader who asked for double-size text got an 11pt checkbox beside 28pt words:
the one element on the page the preference did not reach. They come from the
spacing unit now, which already carries the scale, at a ratio that leaves the
default and high-contrast sizes where they were. The marker's centre and its
label's origin follow from the marker, so the gap on either side of it stays
one spacing unit at any scale.

So does every other affordance the reader has to see or hit. The slider track
came from the focus ring's width for the same reason the marker did, and the
slider **thumb** and the **scrollbar** were not applied at all — they sat at
their construction defaults for the life of the process, so a reader at
double-size text got an 8pt scrollbar and an 8pt thumb beside a touch target
the same preference had already doubled. Each ratio lands on the value that
default was, so nothing moves until a preference asks it to.

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

## A mark contrasts with its control, not with the palette

`apply_palette` resolves control marks from the **system** palette; an
application paints its **own** surfaces. Nothing made those two agree, and the
combination is not exotic: a reader on a light system running an app that draws
dark got the light palette's near-black mark on a near-black control. Measured
in the showcase, the empty checkbox border came out at luminance 19 against a
surface of 56 — a gap of 37, where the dark palette's own mark manages 145. In
high contrast, of all preferences: the one whose entire purpose is that gap.

The framework already knows the surface and already has a rule for choosing ink
to put on one — it is what picks the tick inside a filled checkbox. A mark that
fails `MARK_CONTRAST_MINIMUM` against its own control is replaced by that ink at
the mark's own alpha; a mark that passes is left exactly as the palette
resolved it.

This was found by rendering the mixed case rather than by reasoning about it.
`showcase-skia-contrast-light.png` is the light-palette high-contrast tokens
over the showcase's own dark surfaces, and the render gate requires it to
differ from the dark one.
