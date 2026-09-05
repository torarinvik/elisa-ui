# Responsive layout policy

`UiResponsive` keeps adaptive layout decisions in Elisa. Applications provide
logical viewport dimensions and, when needed, their own compact/medium/expanded
breakpoints; no backend or OS name is required.

```elisa
include "src/widgets/ui_widget.elisa"

points: UiResponsive::Breakpoints = UiResponsive::defaults()
mode: UiResponsive::SizeClass = UiResponsive::classify(available_width, points)
layout_axis: UiConst::Axis = UiResponsive::axis(
    available_width, points,
    UiConst::Axis.Column, UiConst::Axis.Row, UiConst::Axis.Row)
columns: i32 = UiResponsive::columns(available_width, 180.0, 16.0, 4)
cards: UiWidgets::Widget = UiWidgets::adaptive_grid(
    available_width, 180.0, 4, 16.0, 16.0, surface)
```

All dimensions are normalized as nonnegative finite values. Breakpoints are
ordered during normalization, column counts are clamped to at least one and a
caller-supplied maximum, and `physical_extent` converts a logical target to a
minimum physical size using the declared scale. This keeps narrow windows,
large text, and high-density touch targets deterministic across SDL, AppKit,
WasmBrowser, and the headless harness. `UiWidgets::adaptive_grid` applies the
same bounded policy to the retained hierarchy, so a resize handler can rebuild
the composition without copying breakpoint logic into every screen.
