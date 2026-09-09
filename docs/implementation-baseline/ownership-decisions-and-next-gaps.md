# Ownership decisions and next gaps

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


- Elisa owns retained widget/resource-visible state, layout, interaction,
  themes, semantic generation, text editing, frame scheduling decisions,
  lifecycle interpretation, back-navigation decisions, and application-visible
  errors.
- Native/host hosts own OS objects, native event queues, text
  shaping/rasterization, GPU/image mechanisms, accessibility protocol objects,
  package delivery, and service authority. After translation, `UiEvents` owns
  the bounded Elisa-side FIFO and its overflow policy; shims pass raw facts and
  explicit framework decisions.
- AppKit native-control read-back is routed through the same Elisa-owned,
  autorelease-scoped bridge wrapper surface as construction and mutation; the
  realization module no longer imports raw Cocoa query symbols.
- The AppKit native bridge keeps ABI declarations, autorelease-scoped control
  operations, and diagnostic read-back in separate Elisa modules, so adding a
  native fact cannot silently widen realization policy or push framework state
  into Objective-C.
- The hosted backend consumes the authoritative SDK-generated host bindings from
  the staged `sdk/elisa/wasmbrowser/` source root; standalone builds select that
  checkout through `ELISA_UI_WASM_SDK`, while the SDK integration stages its own
  resolved dependency. Elisa retains only the UI-specific policy and canonical
  record lowering around that imported ABI.
- The C boundary now exposes a packed ABI version from Elisa and checks it
  against the public header in `scripts/check_capi.sh`; wire ordinals, record
  layout, counted committed text, and counted IME composition (with scalar-range
  clamping) remain documented in `include/elisa_ui.h` and are exercised by the
  C bridge checks. The same header is compiled as C11 and C++17 in that gate,
  preserving the opaque boundary for either host language. Event/viewport
  conversion remains in `ui_capi.elisa`, while the bounded text staging slot
  and committed/IME policies live in the focused `ui_capi_text.elisa` extension.
  The C app callback now receives an opaque, generation-scoped
  `elisa_ui_widget_handle`; the adapter converts the legacy Elisa slot in
  `ui_capi_widget.elisa`, so raw retained-arena indexes are no longer a stable
  public ABI. `test/capi_widget_handle_test.elisa` covers token changes across
  tree reset/rebuild.
  The executable C host is now the tracked
  [`examples/capi/c_host.c`](../examples/capi/c_host.c) example, and the C++17
  header consumer is tracked beside it; the check script compiles those real
  examples instead of generating temporary source, so the documented boundary
  remains runnable and reviewable.
- Elisa text navigation now applies the UAX-style Hangul L/V/T/LV/LVT join
  rules in the shared grapheme walker, so decomposed Jamo and precomposed
  syllables keep atomic caret/deletion behavior; `widget_layout_text_test.elisa`
  covers both forms alongside the existing emoji and combining-mark cases.
- The grapheme walker now keeps its bounded Unicode property tables and public
  next-boundary operation in the backend-neutral `ui_text_grapheme.elisa`
  module. Both flat editing and `ui_text_layout.elisa` call that one
  Elisa-owned implementation. Controls, Prepend characters, common Indic
  SpacingMarks/linkers, supplementary variation selectors, and
  Extended-Pictographic ZWJ context are covered by deterministic text tests;
  non-emoji ZWJ sequences no longer swallow their following scalar, and line
  wrapping cannot split combining or emoji ZWJ clusters.
- The common Indic SpacingMark ranges now include their extended vowel-sign
  forms while preserving virama/linker precedence, so longer Devanagari,
  Bengali, Gujarati, Tamil, Telugu, Kannada, and Malayalam clusters retain
  atomic caret and deletion behavior.
- `UiTextMeasureLayout` adds a bounded pixel-width planner beside the
  scalar-column `UiTextLayout`. Its core accepts an Elisa width-provider
  function, the default facade uses `UiTextMetrics`, and `UiSkia::layout_text`
  supplies Skia's own metric query. It preserves source ranges and CRLF
  handling, prefers complete whitespace-run breaks, and emits an oversized
  grapheme as one line instead of stalling; the active backend remains the
  authority for font metrics.
- Bounded Elisa scans that return a derived value now use scoped `for`
  expressions where an early result is the only loop state, including the
  UTF-8 prefix, scalar-count, and UTF-16-count walks in `UiText`, plus
  grapheme/UTF-16 boundary, caret, word-navigation, secure-mask, and
  marked-text walks in `UiFlat`. The flat layer delegates UTF-8 prefix
  validation to `UiText`, leaving one malformed-input policy for every text
  owner. Structural tree traversals and editing state machines remain explicit
  `while` loops because they follow mutable links or carry multi-step mutation
  budgets. The persistence duplicate-ID scan and retained visible-text scan are
  also scoped and fail closed on malformed record bounds. The C text-buffer
  scrub check is covered by the existing bridge tests and keeps mutable state
  local to the expression. Retained sibling-link insertion now uses the same
  scoped traversal form with an explicit exhaustion guard, so malformed child
  chains cannot append after a bounded scan has lost its terminator.
- Pixel text hit-testing, caret placement, and grapheme-flooring now use the
  same scoped `for` form over the shared `MAX_TEXT_BYTES` budget. Their result
  state is explicit (`hit`, accumulated x, or floor offset), so every walk is
  bounded even when a hostile text view or metric provider fails to make
  progress.
- Deferred Skia callback drawing now has parity for rounded gradients and
  rounded-rectangle shadows. Both helpers retain explicit Elisa geometry/effect
  policy and replay through the existing clip, gradient, and shadow primitives;
  no additional C/Objective-C state or hosted command shape is required.
- Deferred convex-polygon helpers now reserve their full triangle/line
  expansion before enqueueing, so a fixed-queue overflow rejects a complete
  custom shape rather than presenting a partial fan or outline.
- Deferred clip and transform scopes now carry a typed Elisa-side LIFO ledger
  and replay through the immediate save/clip/transform helpers. Mismatched pops
  and depth exhaustion are rejected before any native restore can target the
  wrong scope; depth exhaustion also reports `CommandOverflow` so callback
  content cannot be silently dropped.
- `UiSkia::Snapshot` now includes deferred activity, count, overflow, and scope
  depth alongside attachment/save/resource diagnostics, keeping callback
  failures observable without exposing a canvas or mutable queue storage.
- The shared event queue now rejects typed key, pointer-button, and gamepad
  ordinals that normalize to `Event.None`, instead of reporting a successful
  enqueue for a silently discarded no-op. The queue retains its existing
  finite-coordinate normalization and authoritative overflow replacement.
- `UiCapabilities::select_skia_renderer()` now requires a genuinely local
  custom-paint profile: hosted WasmBrowser and native-control profiles retain
  their authoritative renderer instead of being relabeled as Skia. The
  capability regression checks both the rejection and the unchanged renderer.
- The SDL3 scanline range conversion now lets the range advance its circle row
  index exactly once; a leftover manual increment had been skipping alternate
  rows after the earlier integer-loop safety refactor. The native hello build
  and dummy-video smoke path pass with the corrected raster loop.
- The SDL_ttf text bridge now passes an explicit four-byte `SdlColor` aggregate,
  matching the library's `SDL_Color` parameter instead of depending on a
  packed-integer calling convention; the native hello build and dummy-video
  smoke path pass with that ABI declaration.
- The Skia attachment entry point now enforces the same capability gate as the
  profile selector: hosted WasmBrowser and native-control profiles detach and
  reject a borrowed canvas instead of silently claiming local Skia. The Skia
  painter regression covers the rejected hosted attach.
- AppKit's bounded native-string copy now preserves `CFStringGetBytes`' UTF-16
  conversion count. When a fixed buffer ends before a multibyte scalar, the
  canvas text adapters return their capacity sentinel so `UiFlat` retains its
  truncation diagnostic instead of treating the clipped IME/accessibility edit
  as complete; the key-map test covers the 1023-byte-plus-`é` boundary.
- AppKit c-string equality now rejects either null pointer before entering the
  bounded byte scan, so malformed native titles cannot alias an empty string;
  the key-map regression covers both null-left and null-right cases.
- Skia command replay now applies zero-area retained clips through a private
  replay-only save/clip scope, matching SDL3 and CoreGraphics empty-clip
  behavior while preserving the public direct-clip helper's fail-closed input
  contract. The painter regression verifies the extra scope is balanced.
- The Skia direct-painter path now shares one private Elisa geometry policy with
  command replay. Coordinates/extents are bounded, empty primitive geometry is
  rejected, and rounded radii are clamped to half the shortest edge before FFI;
  `test/skia_painter/abi_and_command_batch.elisa` and `immediate_painting.elisa`
  record the radius clamps, and the source-size gate keeps `ui_skia_geometry.elisa` cohesive.
- Skia image/typeface bindings now expose generation-safe `prune_bindings()` and
  `clear_resource_bindings()` teardown paths. Draw, bind, and metric queries
  automatically discard non-ready or disposed logical resources before any
  borrowed pointer can be used; the headless Skia fixture covers both resource
  kinds and the combined teardown helper.
- Skia image filtering is an explicit Elisa `ImageSampling` policy with a linear
  default and an opt-in nearest-neighbour path. The FFI carries only the small
  enum ordinal; the C++ shim translates it to `SkSamplingOptions` while invalid
  values are normalized in Elisa. `test/skia_painter/immediate_painting.elisa`
  verifies the nearest path without opening a surface.
- An invalid Skia attachment (`canvas == 0`) now enters the same Elisa-owned
  surface-loss path as explicit recreation and advances the generation token;
  `test/skia_painter/surface_lifecycle_and_scopes.elisa` covers the stale-surface
  distinction.
- Surface loss now clears all borrowed Skia image/typeface bindings while
  preserving logical `UiResources` records, forcing hosts to rebind fresh
  renderer objects after device/surface recreation; the Skia fixture verifies
  both binding kinds are no longer paintable after loss.
- Canvas-independent Skia metrics are isolated in `ui_skia_text.elisa`, keeping
  text authority separate from surface lifecycle and replay primitives while
  preserving the bounded FFI contract and headless metric coverage.
- Generation-bound Skia text now has Elisa-owned primary/fallback selection for
  drawing, width, ascent, and line-height queries. A fallback is used only
  when the primary resource is not ready or has no live typeface binding;
  per-glyph shaping fallback remains the host typeface/shaper's authority.
- Skia custom controls now have explicit Elisa-owned translation/scale scopes in
  `ui_skia_transform.elisa`. A shared save-depth ledger restores frame, clip,
  and transform state on detach/surface loss; the headless recorder verifies the
  transform FFI calls, balanced saves, and recovery when a control forgets to
  pop its transform.
- AppKit creates its temporary SkCanvas after `app_frame`; the Skia adapter now
  provides an explicit Elisa-owned deferred side-band queue in
  `ui_skia_deferred.elisa`. `begin_deferred_frame()` brackets the callback,
  `defer_*` helpers copy bounded values/text and capture retained command
  anchors, and replay interleaves the two streams in application order. Queue
  overflow reports `CommandOverflow`, while surface loss cancels copied work;
  the hosted six-command ABI and native object ownership remain unchanged.
- The real showcase now has an application-level headless workflow in
  `test/showcase_workflow_test.elisa`: it builds the shared `examples/hello`
  tree, verifies retained custom vector commands and semantics, drives pointer
  focus plus UTF-8/IME editing and an invalid-to-valid validation edit, saves/
  restores application state, and replaces a failed resource generation before
  the next frame.
- `test/unicode_conformance_test.elisa` carries focused UAX #29 regressions,
  while `scripts/check_unicode_conformance.sh` generates a bounded Elisa
  fixture from all 1,187 rows of the pinned Unicode 15.1.0
  `GraphemeBreakTest.txt`. The retained editor and layout walkers therefore
  have full conformance evidence separate from renderer-specific helper tests.
- `test/skia_offscreen_host.cpp` repeats complete real SkSurface frames and
  reports render total/average nanoseconds, while `docs/ui-performance.md`
  records the distinction between retained-tree safety ceilings and actual
  raster evidence. The host rejects zero-duration samples and the showcase
  host checks rasterized title ink in addition to shape pixels. The required
  shell gates run each host in two fresh processes and compare logical pixel
  digests, making the evidence reproducible beyond one process lifetime.
- `test/showcase_skia_test.elisa` and `test/showcase_skia_host.cpp` extend that
  evidence to the shipped hello application: the required real-Skia gate drives
  its public text/input, validation, state, and resource-replacement workflow, then checks
  command/semantic counts, retained custom-art pixels, a PNG snapshot, and
  repeated frame timing on an 800x680 raster surface. The host binds a
  deterministic decoded image; Elisa queues the old resource generation,
  rotates it through retry, and queues the replacement before replay. Pixel
  checks require the stale generation to remain the Elisa placeholder and the
  replacement generation to paint and requires ink from the edited text field
  inside its live retained bounds, including a selected grapheme-safe prefix
  painted with the active accent, plus the final validation status label. The
  same application fixture anchors
  deferred orange/cyan/magenta artwork to the live content card and checks the
  overlap pixels, proving deferred work is ordered before, between, and after
  retained commands rather than being an overlay-only pass.
- Immediate Skia clip and transform scopes now fail closed at an Elisa-owned
  depth budget. Rejected pushes make no native calls; transform pushes report
  rejection so callers cannot accidentally pop an older scope, while detach
  still restores every accepted scope. Retained replay remains bounded
  separately by `UiCore::MAX_COMMANDS` so empty-clip command balance is
  unchanged.
- Rounded custom clips now use the same typed save/pop ledger, with Elisa
  clamping the radius before the bridge calls Skia's `clipRRect`. The Skia ABI
  minor version moved to `2` for that additive entry point, and rounded
  gradients are composed entirely in Elisa from the clip and two-stop gradient
  helpers.
- Immediate custom circles now have a true Elisa-validated stroke path in
  addition to fills; the Skia bridge only selects its existing stroke paint and
  draws the circle, with ABI minor version `3` recorded by the C++ header check.
- The narrow Skia declarations are now published in `include/elisa_skia.h` and
  included by both the production C++ bridge and headless recorder, so host ABI
  drift is caught at compile time without widening the Elisa boundary. The
  header and Elisa module now also expose a packed `elisa_skia_abi_version()`
  check before an opaque canvas, image, or typeface handle is submitted.
- Generation-safe Skia image helpers preserve the typed nearest/linear sampling
  choice through both ready-resource and bound-resource draw paths; the
  headless painter fixture covers each form.
- WasmBrowser clipboard staging and guest-memory/text-metric policy now live in
  the private `ui_wasm_host_state.elisa` module. Only the required top-level
  hook names and WIT guest exports remain at the component boundary; the
  hosted package build and inspection fixture continue to pass.
- The Skia C boundary no longer publishes an unused raw rectangle primitive;
  retained rectangles always use Elisa's shared rounded-style policy, keeping
  the host shim and public header limited to exercised operations.
- Skia transform scopes now include finite degree-based rotation alongside
  translation/scale. All three scopes share the Elisa save-depth recovery path,
  including detach-time restoration of forgotten rotation scopes.
- The direct Skia transform bridge now rejects non-finite translation/rotation
  and non-positive or non-finite scale values before touching a borrowed
  `SkCanvas`; the real CPU-raster fixture verifies malformed transforms are
  no-ops and cannot poison the following Elisa frame.
- The same native boundary now rejects finite coordinates, extents, radii,
  stroke widths, shadow offsets/blur, and text sizes outside Elisa's bounded
  geometry domain; hostile direct calls are covered by the real raster host.
- Skia circle normalization now also bounds the radius against both center
  axes, accounting for half the stroke width on stroked circles so the full
  disk stays inside the finite geometry envelope before the FFI; the native
  bridge applies the same derived-edge rejection to direct foreign calls.
- Retained Skia replay now routes circle, triangle, and hairline-line commands
  through the same Elisa primitive helpers as immediate custom drawing, so
  geometry and alpha validation cannot drift between paint entry points.
- Skia's shared outline and hairline style lowering now uses those same
  primitive helpers, leaving `ui_skia_style.elisa` with visual-token selection
  only and removing duplicate direct FFI calls.
- Immediate Skia custom drawing now has a dedicated `ui_skia_clip.elisa`
  extension. It rejects empty clips before FFI and shares the transform/frame
  save-depth ledger, with headless coverage for direct clip balance and cleanup.
- `ui_skia_state.elisa` now exposes an immutable Skia renderer snapshot and
  balance predicate covering attachment generation, save/clip/transform depth,
  and active image/font bindings; the headless fixture verifies detached
  surface state and cleared bindings without exposing native pointers.
- Skia replay now returns a typed `RenderStatus` (`SkippedNoSurface`, `Complete`,
  or `CommandOverflow`) while retaining `render()`/`render_checked()`
  compatibility; the headless fixture distinguishes detached and overflowed
  frames.
- The typed Skia render status is also exported through normal and scaled
  one-shot C entry points, preserving legacy void exports while making
  no-surface and command-overflow outcomes observable to hosts.
- Skia shadow blur and offsets now cross the FFI as explicit arguments selected
  by Elisa; the C++ bridge constructs only the target-specific `SkPaint` effect
  and no longer embeds appearance defaults.
- Skia outline and line stroke width now cross the FFI as an explicit Elisa
  style value; invalid non-positive widths are rejected at the native boundary
  rather than replaced with a hidden bridge default.
- Skia font-size normalization now lives in `ui_skia_text.elisa` and is shared
  by default and bound metric/draw calls; the C++ bridge rejects non-positive
  sizes instead of silently selecting an implicit fallback.
- Rectangle elevation is now explicit in Elisa: `UiCore::fill` records a plain
  surface while `UiCore::fill_elevated` marks intentional control surfaces in
  side-band command metadata. Skia and CoreGraphics consume the same
  `UiPaint` policy, and SDL3/Wasm preserve their existing wire payloads while
  ignoring the visual hint. The Skia fixture verifies same-sized plain and
  elevated rectangles remain visually distinct at replay time.
- The AppKit/Skia compositor now forwards logical and backing-pixel dimensions
  to Elisa, where `UiCore::backing_scale` selects the finite
  aspect-preserving scale. The C++ host retains only pixel-extent validation,
  temporary-surface allocation, and CoreGraphics presentation.
- The AppKit/Skia compositor presents its pixel raster into logical view bounds
  so AppKit's device transform performs the backing-scale conversion exactly
  once. A headless 2x CGContext fixture verifies shapes and glyphs remain in
  the expected physical locations instead of being enlarged a second time.
- Shared custom-painter constants now live in `UiPaint::RoundedRectStyle`.
  CoreGraphics and Skia consume the same Elisa-owned shadow, hairline, radius,
  and alpha values; the Skia extension only lowers them to its primitive FFI.
- The Flat compatibility painter explicitly elevates radio-button and checkbox
  surfaces alongside push/toggle buttons and text fields, preserving the
  control appearance that the old dimensional heuristic provided without
  making sliders, progress tracks, or containers look elevated.
- Direct Skia text drawing now goes through the same Elisa sanitization as
  retained replay, keeping custom-control escape hatches bounded and UTF-8
  safe without duplicating policy in the bridge.
- Measured Skia text now exposes Elisa-owned line hit testing that returns only
  grapheme-boundary byte offsets, reusing the active backend width authority so
  caret/selection coordinates cannot split combining marks or emoji clusters.
  The same operation is available through the backend-neutral
  `UiTextMeasureLayout::hit_test()` facade.
- The measured text pipeline now also maps byte offsets back to caret x
  coordinates, flooring offsets inside a grapheme to its leading edge through
  the active backend metric provider.
- Skia rounded-corner radii now cross the FFI after Elisa geometry
  normalization; the C++ bridge forwards them to `SkRRect` without a duplicate
  radius fallback and rejects malformed direct values.
- The headless Skia painter regression now asserts that an Elisa-provided theme
  radius reaches the recorder-backed round-rect primitive unchanged after
  normalization, making themed custom-surface styling reproducible without
  foregrounding a window.
- AppKit canvas accessibility storage reset now uses a bounded scoped `for`
  expression, keeping fixed-capacity cleanup in Elisa without loop-counter
  mutation; the off-screen canvas bridge check remains green.
- Resource demand counting now uses the same scoped reduction form for its
  bounded slot scan, preserving deterministic ordering while removing mutable
  accumulator plumbing from the public policy module.
- Resource live-count inspection now uses a scoped bounded reduction as well,
  keeping resource queries allocation-free and free of mutable counter setup.
- `UiInspector::Frame` now includes the aggregate `UiResources::Snapshot`, so
  requested/ready/failure/cancellation pressure is visible to diagnostics
  without exposing resource storage or borrowed renderer handles.
- `UiInspector::Frame` also includes the value-only `UiRemote::Snapshot`, making
  negotiated presentation, scale, generation, and input-overlay state visible
  through the same cross-backend diagnostics surface.
- AppKit custom-canvas CoreText shaping and metrics now live in their own
  `ui_appkit_canvas_coretext.elisa` extension; window/snapshot ABI types and
  text-command routing remain separate modules with the same public contract.
- Callback entry points are lifetime-guarded: if an application handler resets
  the flat tree, post-callback history, composition, activation, adjustment, and
  radio state updates are abandoned instead of touching recycled slots. This is
  covered by `test/widget_reentrancy_test.elisa`; AppKit pointer-down, text
  command, composition, accessibility, and inactive-window adapters now apply
  the same epoch/lifecycle guard before continuing native work.
- Pointer button ordinals are a closed five-value Elisa vocabulary (primary,
  secondary, middle, back, forward). C/WIT records and native SDL/AppKit
  ingress reject unknown values before constructing typed events; the published
  values and focused key-map regressions live in `include/elisa_ui.h`,
  `test/event_wire_test.elisa`, `test/sdl3_keymap_test.elisa`, and
  `test/appkit_canvas_keymap_test.elisa`.
- Key, gamepad-button, and gamepad-axis enum casts are rejected in both event
  directions: invalid typed values flatten to a rejected sentinel, while raw
  records decode to `Event.None`. `test/event_wire_test.elisa` covers the
  boundary.
- `UiFlat` carries the closed `UiConst::WidgetEvent` enum through all control,
  editing, keyboard, and accessibility paths; one private Elisa helper performs
  the final ordinal conversion required by the legacy `app_widget_event` ABI.
- `UiResources` is a small public facade over cohesive Elisa modules for
  bounded logical-resource identity, progress, cancellation,
  retry and generation-safe disposal, including owner-scoped teardown helpers
  and idempotent visibility/prefetch demand priorities. Host/SDK layers still
  own verified bytes, transport, cache and decode/upload authority; resource
  transitions raise the shared resource/paint invalidation reasons, and its
  aggregate snapshot reports bounded loading/ready/failure counts. Identifier
  storage is scrubbed when the resource table resets. A focused metadata
  extension records validated intrinsic image/document dimensions per live
  generation, preserving them across retry and clearing them on disposal so
  presentation can reserve stable geometry without backend-specific state.
  A terminal/offline/denied generation cannot be revived to `Ready` in place;
  only an in-flight `Requested` operation may complete successfully, so late
  host results must cross an explicit retry generation boundary.
  Counted resource keys are identities rather than display text: malformed
  UTF-8, null-backed, clipped, and over-capacity views are rejected before
  lookup or storage, so a bad key cannot alias a valid prefix. Coverage lives
  in `test/resource_state_test.elisa`.
- `UiResourcePresentation` maps those lifecycle states to explicit
  placeholder/loading/ready/fallback records, declared-or-intrinsic reserved
  geometry, independent progress visibility and retry affordances. Kind-specific
  defaults and all presentation decisions remain in Elisa; hosts only resolve
  verified resource data into renderer objects. Coverage lives in
  `test/resource_presentation_test.elisa`.
- `UiResourcePresentation` also exposes combined request-and-demand helpers for
  visible assets, records demand state/priority in each presentation snapshot,
  and clears only the generation's visibility hint without cancelling the
  logical resource. Repeated helpers coalesce by identifier and update the
  owner/priority in place; invalid keys remain neutral. Coverage lives in
  `test/resource_presentation_test.elisa`.
- `UiFeatureView` is the optional-code counterpart to resource presentation:
  it records a bounded `(feature, interface, package)` identity, requires a
  nonzero host activation token, accepts only generation-matching poll facts,
  preserves that token through cancellation for explicit host deactivation,
  and rotates generations on retry. `UiHarness` and `UiInspector` expose the
  same state without introducing a downloader, linker, or native pointer;
  coverage lives in `test/feature_view_test.elisa` and
  `test/ui_harness_test.elisa`.
- `UiVirtualList` owns bounded geometry and semantic-window policy for long
  lists. Logical total count, before/after edges, and off-screen focus or
  selection indexes remain available even when row widgets are not realized;
  coverage lives in `test/virtual_list_test.elisa` and
  `test/virtual_list_semantics_test.elisa`.
- `UiConstraints` owns finite minimum/preferred/maximum normalization and
  reports repaired conflicts and allocation clamping without adding state to
  every widget handle. Coverage lives in `test/constraints_test.elisa`.
- `UiDialog` owns bounded modal ordering, typed result persistence, owner-scoped
  cancellation, back navigation, and a portable Dialog semantic projection;
  AppKit maps that role to its stable group-container token. The AppKit canvas,
  SDL3, and WasmBrowser input adapters consume Escape through this same policy
  before delivering it to application code. Coverage lives in
  `test/dialog_test.elisa` plus the backend dispatch fixtures above.
- `UiGestures` owns deterministic eight-contact capture, tap/long-press/drag/
  pinch classification, duplicate/capacity rejection, and lifecycle
  cancellation. Native/hosted adapters still need to translate device facts;
  coverage lives in `test/gestures_test.elisa`.
- `UiResponsive` owns logical orientation and safe-area normalization in
  addition to size classes and touch-target scaling. Hosts provide insets;
  coverage lives in `test/responsive_test.elisa`.
- `UiTextLayout` owns bounded UTF-8 scalar advancement, newline/whitespace
  break points, and deterministic long-word fallback. Renderers still own
  shaping and measured pixel widths; coverage lives in
  `test/text_layout_test.elisa`.
- `UiTextInput` owns purpose-driven keyboard/multiline traits and hardens secure
  fields by denying clipboard, semantic value, autocorrect, and suggestions;
  coverage lives in `test/text_input_test.elisa`.
- `UiIdentity` owns bounded keyed generation transactions for dynamic lists and
  forms, while `UiTheme`, `UiLocalization`, and `UiValidation` keep appearance,
  RTL/plural policy, active-locale revision/invalidation, and revision-safe
  asynchronous field state in shared Elisa modules. The `UiFlat`/`UiHandles`
  palette adapter applies only shared appearance tokens and is idempotent, so
  host refreshes cannot create a dirty loop; per-widget colors and geometry
  remain application-owned. Applying a system theme now also retains the
  normalized preferences/revision used by text-scale and reduced-motion
  consumers, while direct palette overrides remain separate. Each policy is
  covered by a focused headless test.
- `UiValidation` clears its fixed diagnostic-message storage on table reset, so
  retired validation text is not retained across lifecycles; coverage remains
  in `test/validation_test.elisa`.
- `UiInspector` is a read-only, allocation-free diagnostic projection of the
  retained tree and semantic buffer. It reports shared lifecycle phase,
  generation, surface/input/render/focus predicates, deferred layout/frame-
  buffer state, typed relationships, and the raw invalidation mask plus
  monotonic invalidation sequence while redacting secure text. It also exposes
  a bounded task snapshot plus active locale and theme snapshots so lifecycle,
  localization, and appearance-driven rebuilds can be inspected without a
  backend shadow table; coverage lives in `test/widget_inspector_test.elisa`.
- `UiLifecycle::reset()` and `UiLifecycle::stop()` are task-teardown
  boundaries: they reset the bounded `UiTasks` table before a new surface can
  reuse view storage, so a late completion observes an invalid handle. The
  task enum is named `TaskState` to remain unambiguous when resource state is
  included in the same compiler unit; `test/lifecycle_test.elisa` covers both
  stop and restart invalidation.
- `UiMetrics` owns the interpretation of application, semantics, and paint
  stages, monotonic-clock normalization, completion state, retained command and
  semantic counts, overflow flags, invalidation snapshots, and independent
  layout/text/resource work timings. The orthogonal work channels live in
  `ui_metrics_work.elisa`; they support nested kinds with allocation-free,
  duplicate/unmatched-safe scopes. The snapshot includes both the current dirty
  mask and the shared monotonic invalidation sequence, so repeated requests
  remain observable without backend state. Backends supply timestamps from
  their own clocks; no host-specific timing policy is duplicated in the
  inspector or native bridges. Coverage lives in `test/metrics_test.elisa`.
- `UiState` is the explicit application-state persistence hook. It emits and
  validates a bounded versioned record stream keyed only by application-owned
  numeric IDs; failed restores clear the prior snapshot and no framework
  pointer or arena identity crosses the boundary. Save/restore buffers are
  scrubbed on begin, reset, and failed restore. Coverage lives in
  `test/ui_state_test.elisa`.
- `UiCapabilities` owns conservative, typed backend profiles. Adapters select a
  profile at startup; applications and `UiInspector` consume capability facts
  without OS-name branches or native-object queries. Coverage lives in
  `test/capabilities_test.elisa`.
- `UiEvents` owns bounded FIFO ingress after each adapter has translated native
  facts into `UiCore::Event`. Synchronous adapters drain immediately; SDL drains
  poll bursts. Full queues reject ordinary physical input, while authoritative
  quit/resize/focus facts may replace the oldest stale input so teardown cannot
  be stranded; sticky loss facts remain visible through `UiInspector`; reset
  clears queued variant payloads as well as counters. Coverage lives in
  `test/event_queue_test.elisa`.
- `UiCore::begin_frame` clears the previously used command and semantic slots,
  releasing stale borrowed text views while retaining the fixed allocation-free
  buffers. The C counted-text bridge and AppKit canvas teardown likewise scrub
  their Elisa-owned staging strings after use.
- Raw `UiCore::Command.DrawText` values are normalized again at the retained
  frame boundary, covering callers that bypass the convenience constructor and
  keeping origin, font size, and counted UTF-8 text safe for every backend.
- SDL event dispatch now ends the current native loop immediately when a text or
  regular event callback stops the lifecycle or starts a new generation, so a
  final callback cannot be followed by one stale application frame. The
  lifecycle-stop fixture covers both queued and direct text callbacks.
- AppKit read-back helpers expose only native facts. The button-toggle
  introspection path now performs the native click as one primitive while Elisa
  owns the before/after comparison and state restoration; no test behavior is
  encoded in the Objective-C shim.
- `UiControls` owns bounded copies of retained captions before a native backend
  applies its control list. This prevents labels, titles, and button text from
  retaining caller-owned transient `sview` buffers; `test/controls_test.elisa`
  covers the lifetime guarantee.
- `UiHarness` is the deterministic Elisa-side test driver. It injects a
  monotonic clock, typed lifecycle/input events, resource requests/progress,
  and frame boundaries while leaving production event-loop ownership with each
  backend; `UiLifecycle` centralizes session generations and phase predicates,
  stopping resets resource generations so late completions are ignored; coverage
  lives in `test/ui_harness_test.elisa` and `test/lifecycle_test.elisa`.
- `UiCore::Invalidation` is the shared dirty model for layout, paint, semantics,
  resources, and animation scheduling. Frame-local reasons clear at
  `begin_frame`, while layout/resource reasons remain until an owner resolves
  them; `UiInspector::Frame` exposes the five states, current bit mask, and a
  monotonic sequence that advances on every non-empty request, even when a bit
  is already dirty. `test/core_invalidation_test.elisa` covers the lifecycle.
- `UiCore::frame_timeout_ms` owns deterministic conversion from animation
  seconds to bounded native wait milliseconds. `UiSdl3::animation_timeout` is
  retained only as a compatibility forwarding name; SDL supplies the final
  event-queue call.
- `scripts/check_wapp.sh` is now the compiler-independent hosted package
  fixture: it inspects an existing `.wapp` through WasmBrowser's CLI and
  asserts the profile, host imports, guest exports, and absence of JS/TS/ESM
  artifacts. The public `UiHandles` builder covers all flat constructors,
  typed state setters/queries, event forwarding, hit testing, accessibility
  actions, and text editing with stale-handle guards. The shared hello example
  is migrated to that surface across all three entrypoints. Android/iOS and remote
  work remain blocked on sibling host/SDK execution fixtures rather than being
  simulated here; the hosted adapter now consumes generated SDK bindings while
  retaining only its UI-specific lowering in Elisa.
- The typed `UiHandles` facade is now split into four cohesive Elisa modules:
  identity/tree lifetime, builders, styling/queries, and interaction/editing.
  The public include path and stale-handle behavior are unchanged; all modules
  remain below the 400-line source hygiene limit and the existing handle test
  covers the assembled surface.
- `UiHandles::parent_index` now applies the same stale/container validation as
  the typed builders before exposing its legacy slot escape hatch; stale or
  leaf parents return `UiFlat::NONE` instead of a potentially recycled index.
  Coverage lives in `test/widget_handles_test.elisa`.
- `UiHandles::event_is` and `UiHandles::callback_matches` keep the unavoidable
  legacy widget-event ordinal/slot callback seam typed and stale-safe for
  applications, so the shared hello view no longer repeats raw integer/index
  comparisons.
- `UiHandlesPersistence` is an optional Elisa extension over `UiState` that
  binds text, numeric, and selection values to live typed handles. It rejects
  secure fields, mismatched widget kinds, stale identities, and missing IDs;
  `test/widget_handles_test.elisa` covers save/restore and the privacy rule.
- AppKit canvas menu labels, selector mapping, shortcuts, modifier policy, and
  bounded title composition now live in the dedicated private
  `ui_appkit_canvas_menus.elisa` extension. The remaining canvas private module
  contains accessibility, drawing, and window helpers; the native shim remains
  unchanged.
- The shared hello reference app now keeps its application state adapter in
  `examples/hello/state.elisa` and demonstrates typed P/R save/restore through
  `UiHandlesPersistence`; the in-memory blob is ID/value-only and never stores
  widget handles or secure text. Its `examples/hello/catalog.elisa` module
  provides a typed list/detail interaction and persists the selected item with
  the form state across restore. Its `examples/hello/resource_demo.elisa`
  module drives optional-resource loading progress, completion, retryable
  failure, and recovery through the lower-level `UiResources` state API; the
  host still owns verified bytes and decoding.

The authoritative generated WasmBrowser Elisa bindings are staged in
`../wasm-sdk/sdk/elisa/wasmbrowser/`; the hosted adapter includes those bindings
directly and keeps its UI-specific lowering local to the adapter.
