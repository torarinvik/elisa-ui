# Responsive layout policy

`UiResponsive` keeps adaptive layout decisions in Elisa. Applications provide
logical viewport dimensions and, when needed, their own compact/medium/expanded
breakpoints; no backend or OS name is required.

```elisa
include "src/widgets/ui_build.elisa"
include "src/widgets/ui_handles.elisa"

points: UiResponsive::Breakpoints = UiResponsive::defaults()
mode: UiResponsive::SizeClass = UiResponsive::classify(available_width, points)
layout_axis: UiConst::Axis = UiResponsive::axis(
    available_width, points,
    UiConst::Axis.Column, UiConst::Axis.Row, UiConst::Axis.Row)
columns: i32 = UiResponsive::columns(available_width, 180.0, 16.0, 4)
cards: UiWidgets::Widget = UiWidgets::adaptive_grid(
    available_width, 180.0, 4, 16.0, 16.0, surface)
```

For a retained tree, a resize handler can change a panel's main axis in place:

```elisa
axis: UiConst::Axis = UiResponsive::axis(
    available_width, UiResponsive::defaults(),
    UiConst::Axis.Column, UiConst::Axis.Row, UiConst::Axis.Row)
UiHandles::set_panel_axis(actions, axis)
```

`set_panel_axis` only targets ordinary panels, not scroll or virtual-list
content axes. Reflow keeps child handles, focus, and editing state; layout,
paint, and semantics are invalidated together. `test/widget_responsive_axis_test.elisa`
and the responsive Showcase Forms test cover the retained path.

Responsive forms measure the current retained action captions rather than
assuming source-language strings. `ShowcaseForms::adapt_to_width` also watches
`UiLocalization::revision()`, so an app that replaces captions for a locale
change can remeasure and switch to a stacked arrangement at the same viewport
width. `showcase_forms_responsive_test` exercises longer German action labels
and verifies their width, button identity, and the user's current edit/selection
survive the reflow. The Showcase owns a small English/German action-copy table
and reapplies it on locale changes; this is an example integration, not a
framework-wide message catalog or plural formatter.

All dimensions are normalized as nonnegative finite values. Breakpoints are
ordered during normalization, column counts are clamped to at least one and a
caller-supplied maximum, and `physical_extent` converts a logical target to a
minimum physical size using the declared scale. This keeps narrow windows,
large text, and high-density touch targets deterministic across SDL, AppKit,
WasmBrowser, and the headless harness. `UiWidgets::adaptive_grid` applies the
same bounded policy to the retained hierarchy when a small composition is
rebuilt; `UiHandles::set_panel_axis` supports responsive reflow when retained
identity and state must survive the resize.

`orientation(viewport)` reports portrait, landscape, or square from logical
dimensions. Hosts can pass `insets(top, right, bottom, left)` to
`content_area(...)`; the returned origin and size reserve safe areas in logical
coordinates and clamp oversized/malformed insets to an empty content box.

Software-keyboard occlusion uses `KeyboardInsets` and
`content_area_with_keyboard(...)`. A visible keyboard reserves the larger of
the safe bottom edge and keyboard bottom edge, avoiding double-counting the
home-indicator area; hiding it restores the ordinary safe-area content box.
