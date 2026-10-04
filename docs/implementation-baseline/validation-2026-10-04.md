# Focused validation follow-up — 2026-10-04

This records focused UIKit, AppKit, and GTK native-controls privacy work plus
retained flat-widget text-scale behavior. It does not claim live screen-reader
acceptance or close the broader UI-06 privacy item.

## UIKit native-controls privacy

- The retained `UiControls::ControlState.accessibility_sensitive` bit now
  reaches UIKit controls. The shim applies a generic accessibility label and
  empty value, suppresses placeholder/help, and denies Copy/Cut on its native
  text-field subclass while leaving the field's displayed/editable text intact.
  It restores the prior or content-derived label when sensitivity is cleared;
  caption updates while redacted are retained for that restoration.
- `controls_flat_test` passes assertions for sensitivity state propagation and
  reapplication of text, help, and placeholder on both transitions.
  `uikit_controls_test` passes its native-control mapping/state regression,
  including the neutral default sensitivity state.
- `scripts/build_uikit.sh showcase simulator controls` and the device variant
  both build and sign the retained Showcase app. `scripts/check_uikit.sh` passes
  simulator/device builds, its canvas ABI comparison, fresh-process render
  digest, and boundary guards.
- `check_source_sizes.sh`, `check_global_names.sh`, and `git diff --check` pass.
  No UIKit controls-specific XCUITest, VoiceOver session, or Accessibility
  Inspector run was performed; those remain required acceptance evidence.

## UIKit boundary cleanup

- The source guard no longer rejects legitimate `NSMutableArray` use for
  composing UIKit-owned selection handles and edit-menu items from Elisa-owned
  inputs; it still rejects pre-sized or inline semantic-child construction.
- Removed the obsolete exported `elisa_uikit_touch` callback and unused native
  declaration. UIKit now enters through the identified-contact callback, while
  Elisa's shared touch handler remains an internal route for identified
  contacts.
- Removed an unused Objective-C localization comment literal so the boundary
  guard continues to enforce that displayed framework text comes from Elisa.

## AppKit native-controls privacy

- `scripts/check_appkit.sh` passes both the existing AppKit hierarchy fixture
  and a live Cocoa privacy test. The retained-controls backend now forwards
  `accessibility_sensitive`, applies the generic label, blanks native
  accessibility values for labels, editable/secure fields, buttons, sliders,
  and progress indicators, and suppresses field prompts and accessibility
  help. Clearing sensitivity restores the prior label and the Elisa-owned
  prompt/help values.
- Sensitive AppKit fields receive the window's privacy-aware field editor.
  The fixture verifies Copy/Cut validation is denied while sensitive, direct
  copy/cut leave the editor value intact, and both pasteboard selection-write
  entry points reject export. Clearing sensitivity restores the editor's normal
  Copy/Cut validation.
- The Cocoa fixture verifies that text remains present while its accessibility
  value is empty, edits remain visible during redaction, and button selection,
  slider value, and progress value remain unchanged while their accessibility
  values are blank. It verifies editable/selectable behavior and secure-field
  class retention as well. `scripts/build_appkit.sh hello` links successfully
  with the split privacy shim; source-size, global-name, and diff guards pass.
- `scripts/build_appkit.sh hello` links successfully with the split privacy
  shim; `check_source_sizes.sh`, `check_global_names.sh`, and `git diff --check`
  pass. This is a headless native-object assertion, not an Accessibility
  Inspector or VoiceOver run.

## GTK native-controls privacy

- The GTK controls adapter forwards `accessibility_sensitive`, applies a
  generic accessible label, omits help and entry placeholders, and sets range
  values plus check state to neutral accessibility attributes. Clearing
  sensitivity restores the current native range/check values and retained
  placeholder/help while leaving the visible text/model state intact.
- `scripts/check_gtk.sh` passes its real-widget fixture and a new GTK test
  accessibility fixture covering labels, placeholders/help, ranges, check
  state, restoration, and text entry. A GTK 4.14+ `GtkEntry` subclass
  implements `GtkAccessibleText`, delegating normal text queries to GTK's
  editable delegate but returning empty text/caret/selection/geometry while
  marked sensitive; sensitive caret/selection writes are rejected, while edits
  and the visible model value remain intact. The direct accessible-interface
  fixture passes on macOS GTK 4.24.0 and Linux GTK 4.22.4 under Xvfb. The Linux
  guest has DBus utilities but no AT-SPI bridge/client or Orca, so this does
  not verify the GTK-to-AT-SPI announcement path. The Linux gate now requires
  GTK 4.14+ and compiles the new adapter alongside the shim. The GTK type probe
  was widened from exact
  class-name equality to GTK's `is-a` relation so the legitimate entry subclass
  continues to satisfy the native `GtkEntry` contract. These fixtures validate
  GTK's interface callbacks, not a live Orca/AT-SPI announcement path.
- The GTK gate's symbol-presence check was also fixed: `grep -q` had
  prematurely closed the `nm` pipe under `pipefail`, falsely rejecting present
  Elisa exports.

## Retained flat-widget text scaling

- `UiFlat` now resolves the current normalized text-scale preference against
  each retained widget's base font size at measurement, paint, and text-editing
  geometry queries. Label intrinsic bounds and text-field minimum height
  reflow; the per-widget base size remains unchanged. Restoring the preference
  updates existing widgets without rebuilding the tree.
- New `test/widget_text_scale_test.elisa` verifies doubled label/field paint
  sizes, label measurement, field minimum height, caret geometry, base-style
  preservation, and return to normal scale. It passes, as do
  `widget_layout_text_test`, `widget_theme_adapter_test`,
  `widget_layout_geometry_test`, and `widget_layout_scroll_test` through the
  Stage1 test path. The retained Showcase form now measures its button labels
  against the active text scale, grows button/field minimums, and switches its
  action and plan panels between row and column without rebuilding widgets.
  `widget_responsive_axis_test` verifies reflow, identity/focus preservation,
  normalization, and stale-handle rejection; `showcase_forms_responsive_test`
  verifies narrow and large-text action geometry. It also switches the
  Showcase's action-copy table to longer German captions at the same width,
  changes the locale revision, and
  confirms their measured minimums, stacked layout, stable handles, and edited
  text/selection/focus. The Showcase app's main page is kept in a vertical
  viewport so short windows and keyboard insets can scroll to later content.
  Both focused tests pass through Stage1, and the Showcase
  app entry fixture compiles; this host has no pinned `SKIA_ROOT`, so its
  rendered/device acceptance remains open.

## Win32 native-controls privacy

- The retained sensitivity bit now reaches Win32 controls. A new HWND privacy
  adapter uses `IAccPropServices` to supply a generic accessible name, suppress
  help and values, neutralize range/toggle state, and mark sensitive edits as
  password fields with TextPattern unavailable. A subclass blocks `WM_COPY`
  and `WM_CUT`; native edit placeholders and tooltips are also suppressed.
  Clearing sensitivity removes the annotations, after which normal help is
  applied again. Native display/model state is not rewritten by the adapter.
- `scripts/check_win32.sh` cross-compiles the adapter against MinGW's Windows
  headers and links a PE32+ image against the real import libraries. Its source
  guards check value/state annotation, clipboard blocking, and marker wiring.
  This host has no Windows runtime, so UIA/MSAA behavior, edit TextPattern
  exposure, clipboard behavior on a real HWND, Narrator output, and visual
  behavior remain unverified.
- `check_source_sizes.sh` now passes. The UTF-16 diagnostic-underline and
  IME-composition regression is isolated in
  `test/widget_layout_diagnostic_underline_test.elisa`, preserving its checks
  while keeping `test/widget_layout_visual_test.elisa` within the 600-line
  cap. The Win32 shim/module are within their limits;
  `check_global_names.sh` and `git diff --check` pass as well.

## Reopened regression and portable-corpus validation

- After `applicationDidBecomeActive` began scheduling a view redraw, the full
  `scripts/check_uikit_touch.sh` HID suite passed all nine XCUITests, including
  selection-handle and Unicode preservation across background/resume. The
  separately extracted `widget_layout_diagnostic_underline_test` compiles and
  exits 0 through the Stage1 test path.
- `scripts/check_viewport_three_views.sh` passes on macOS. The Linux corpus
  gate now treats that Metal-only fixture as platform-specific and links its
  existing Android services and Skia test stubs where needed;
  `scripts/check_core_linux.sh` then compiled, linked, and passed all 111
  portable tests on the aarch64 Linux guest, including the retained-axis,
  Showcase Forms responsive, and diagnostic-redaction regressions.
- On the current tree, `scripts/check_core_linux.sh` passes all 116 portable
  tests on aarch64 Linux. This includes the explicit overflow and fractional
  logical-rounding fixtures, plus the same-width locale-change regression for
  translated Showcase Forms actions, expanded localization regression, and
  typed async validation-presentation regression. `localization_test` also
  passes through the native Stage1 link, covering typed plural-form selection,
  fallback, bounded caller-owned count formatting, signed 64-bit minimum,
  repeated placeholders, and UTF-8-safe truncation. The focused validation
  presentation and Showcase Forms tests pass through the native Stage1 link.
  Source-size, global-name, and whitespace checks also pass.
- Source-size, global-name, shell-syntax, and whitespace checks pass after
  these gate changes. The full compiler-only `scripts/run_tests.sh` sequence
  now reaches the end of the test corpus, including the extracted diagnostic
  regression, but exits 1 for two separate reasons: there is no approved exact
  performance budget for this host/compiler tuple, and the adjacent
  WasmBrowser loader panics because
  `cache_package_read_c_api.elisa:41` violates the precondition of
  `cache_package_prefix_progress`. The Android canvas gate skips without
  `SKIA_ROOT`, and the full package smoke skips without a WasmBrowser CLI.
  Strict mode still requires the pinned real-Skia SDK. None of these are
  reported as passing.

## UI-10 retained diagnostic redaction

- `UiFlat::paint` now tags retained commands with their owning widget and
  sensitivity policy. Secure and explicitly sensitive widgets collapse to an
  opaque bounds mask in the parallel diagnostic stream; ordinary renderer
  commands and the native command ABI are unchanged. `UiPaint::replay_diagnostic`
  consumes only that sanitized stream, while trace clients can enumerate it
  through `UiCore::diagnostic_command_*`. A sensitive scroll widget's later
  scrollbar pass has a separate narrow mask, preserving widget-local opt-in.
- `widget_diagnostic_redaction_test` passes through Stage1 and the native link,
  checking ordinary text remains visible, opted-in labels and secure-field
  labels are absent from diagnostic commands, sensitive commands compact to
  masks, late scrollbar paint is redacted, and a new frame resets the policy
  context. `painter_instance_test`
  passes after adding diagnostic replay coverage: ordinary clear commands
  replay normally and a sensitive command is delivered as a fill mask.
- The plan remains open: native-control screenshots/traces and platform-owned
  exporters do not yet consume the portable diagnostic stream.

## UI-07 sizing and constraint diagnostics

- `UiFlat::Widget` now retains declared and effective preferred dimensions;
  `UiFlat::set_preferred_size` and its typed `UiHandles` wrapper accept an
  explicit hint, while zero restores intrinsic/child-derived sizing. The
  measure pass propagates child preferences and layout uses them as the
  allocation and non-stretch alignment baseline.
- `widget_preferred_size_test`, `widget_inspector_test`,
  `widget_layout_geometry_test`, `widget_layout_scroll_test`,
  `widget_layout_overflow_test`, `widget_layout_rounding_test`, and
  `widget_text_scale_test` pass through
  Stage1/native link. Coverage includes
  preferred propagation, weighted growth and max redistribution, cross-axis
  alignment, zero fallback, normalization conflicts, and inspection of
  declared/effective values. Existing max-below-minimum behavior is preserved:
  it remains diagnosable but the contradictory cap is ignored for allocation.
  The explicit `Compress` default preserves legacy underflow behavior;
  `Clip`/`Visible` preserve child minimums after shrinking preferences and share
  the expected clipping policy across rendering, hit testing and semantics.
- Fractional retained geometry is intentionally not snapped per child. Layout,
  paint commands, pointer hit regions, and accessibility frames share the same
  logical `f32` edges; physical-pixel conversion is deferred to the backend
  boundary. `widget_layout_rounding_test` checks fractional allocation, the
  half-open hit boundary, painted rectangles, and semantic bounds together.
- Generation-keyed intrinsic image dimensions now flow from `UiResources` into
  the core image identity and retained measurement without making `UiFlat`
  depend on the full resource subsystem. Metadata changes trigger reflow;
  retries transfer metadata to the replacement generation, while stale refs and
  disposed/reset slots do not retain it. `widget_intrinsic_image_size_test`,
  `widget_image_test`, `resource_state_test`, `resource_presentation_test`, and
  `resource_component_test` pass through Stage1/native link, along with the
  preferred-size, geometry, and inspector regressions.
- The latest `scripts/check_core_linux.sh` run compiles, links, and passes all
  116 portable tests on aarch64 Linux with generation-keyed image metadata,
  explicit overflow policies, fractional-geometry checks, and typed validation
  presentation included.
- Remaining: pixel-identical cross-backend acceptance and broader overflow
  acceptance. The focused native overflow/rounding/layout/scroll/inspector and
  intrinsic-image tests pass on the current host.
