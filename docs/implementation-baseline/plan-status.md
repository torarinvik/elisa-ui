# Workstream status and evidence

_Companion to [implementation-baseline.md](../implementation-baseline.md)._

This maps each workstream in the local implementation plan to its current
evidence and any external blocker. Statuses mean:

- **implemented-tested** — a fixture, gate, or build in this repo exercises it.
- **implemented-elisa-boundary** — the portable Elisa policy is tested, but the
  native/host adapter is a separate integration owned with the sibling repos.
- **blocked-external** — needs a WasmBrowser/SDK/device change this repo cannot
  make without private host access.
- **not-implemented** — no code yet; a real remaining gap.

| ID | Status | Evidence | Remaining blocker |
| --- | --- | --- | --- |
| UI-00 | implemented-tested (compiler-only broad suite partial) | `docs/implementation-baseline*`; current Stage1 product/runtime hashes are recorded in [current validation](current-validation.md); toolchain/resolution/global-name checks, C/Rust/Go bridges, AppKit and Win32 cross-builds, GTK privacy fixtures, UIKit HID suite (9 tests), the 1,187-row Unicode corpus, and 116 portable tests on aarch64 Linux pass; the performance workload completes 21 samples across three processes | latest compiler-only `run_tests.sh` reaches the full test corpus but exits 1 because this host/compiler tuple has no approved exact performance budget and the adjacent WasmBrowser loader fails a proven precondition in `cache_package_read_c_api.elisa`; Android canvas is skipped without `SKIA_ROOT`, the package smoke is skipped without the WasmBrowser CLI, and strict mode requires the pinned real-Skia SDK; live screen-reader and device acceptance remain separate |
| UI-01 | implemented-tested (typed API/native; hosted boundary partial) | public module/boundary inventory; `UiHandles` builders, stale checks and callback identity; `widget_handles_test`, `widget_dispatch_test`, and `widget_reentrancy_test` (including same-slot rebuild from a callback); legacy `app_*` compatibility surface; portable `UiPaint::Painter`/`UiControls::Controls` contracts kept separate from per-platform ABI adapters; generated SDK host imports; dedicated resource/feature runtime smokes and ordinary WasmBrowser package validation | handwritten hosted command/semantic record encoding remains in `ui_wasmbrowser_runtime.elisa`; a new ergonomic application entrypoint remains open; full hosted window/device acceptance remains separate; the SDK does not yet provide the matching typed Elisa command/semantic binding set required for migration; see the [hosted binding gate](hosted-binding-gate.md) and prior SDK contract evidence in [current validation](current-validation.md#hosted-open-vertical-slice-gate-2026-09-18) |
| UI-02 | implemented-tested | `UiLifecycle`, `UiState`, `UiTasks`, `UiEvents`, `UiHarness`; `lifecycle_test` covers both pause/surface-loss orderings and proves focus/resume stay non-renderable until surface restoration; idle wait in `sdl3_wait_event_test`/`sdl3_lifecycle_stop_test`; `UiOwnerLifecycle::dispose_owner` coordinates owner teardown across task/resource/feature/validation/service/dialog/navigation records, with shared-owner, cancellation-tombstone, stale-callback, and idempotence coverage in `owner_lifecycle_test`; `showcase_workflow_test` confirms app initialization preserves unrelated resource owners | none |
| UI-03 | implemented-tested (portable + Apple CPU-raster Skia; integration partial) | `UiCore` commands, `UiRaster`, `UiPaint`, images/gradients/rounded/shadows, text pipeline, `UiTextMetrics` cache, strict direct-ABI UTF-8 validation, geometry validation, explicit per-profile sRGB color-space capability, rectangle-origin-safe retained text caret painting, sealed-hierarchy direct-child overlay ordering with a shared scrim/modal hit floor, Elisa-owned RTL scrollbar geometry/page direction, and SDL text metrics that fail closed consistently when no font is available; `localization_test` verifies locale-revision metric invalidation; `sdl3_text_test` verifies SDL_ttf direction, language, and explicit-script application/reset plus Arabic measurement; `check_skia_offscreen.sh` renders/measures Arabic and Devanagari and tests the bounded Apple Skia shaped-blob cache; `check_showcase_skia.sh` verifies the real retained workflow, generation-bound images, shaped text pixels, and fresh-process replay digests; SDL device-loss and image upload-state fixtures cover logical `Ready` identity and renderer recreation | `text-shaping-and-font-sources.md` records the dependency/font audit; SDL scopes first-strong RTL direction, BCP47 language, and locale script subtag for draw and measure; Apple Skia uses CoreText shaping for ordinary untracked text, but CoreText ignores explicit bidi/script/language iterators and tracked text plus Android retain simple APIs; mixed-script segmentation, fallback policy, mixed-bidi and broader rendered complex-script acceptance remain open; Stage1 currently declines the Showcase AppKit entry and the independent all-pages Skia fixture at call expressions, so those broad render/compositor legs remain unverified; wide-gamut/HDR, cross-device GPU parity, image-resource caching, other-profile shaped caches, and isolated hosted-transfer cost remain open |
| UI-04 | implemented-tested (portable + iOS/Android backends; physical acceptance partial) | `UiResponsive`, `UiMobileSurface`, `UiNavigation`, `UiServices`, `UiCapabilities`; `capabilities_test` verifies `multiple_windows=false` for UIKit/Android canvas and controls, which expose one primary mobile surface; shared counted UTF-8/UTF-16 codec gate; `scripts/check_uikit.sh`, `check_uikit_simulator.sh`, and `check_uikit_touch.sh` pass: canvas/native-controls apps build for simulator/device, ABI and source guards match, UIKit reports real simulator surface/safe-area/trait/lifecycle facts, and HID tap plus committed software-keyboard text round-trip through the retained model/semantics; the retained UIKit native-controls Showcase also builds for simulator and device ([2026-10-04 evidence](validation-2026-10-04.md)); `check_uikit_services.sh` rebuilds the smoke app and uses headless XCUITest on a fresh iOS 26.5 simulator to verify PhotosUI and Files selection, bounded reads, and explicit release; Android ARM64 custom-canvas APK builds and paints on Pixel_9 Android 37.1 AVD with pinned Skia; `check_android.sh showcase` verifies orientation resize/repaint and HOME/resume with a fresh frame; `check_android_ime.sh` verifies composition, visible/hidden insets, and system Back; `check_android_controls.sh showcase` builds the native-controls APK and passes host JNI/export/alignment checks (device half skipped when no device is attached); focused UIKit/Android service tests cover Camera/Microphone adapter state transitions, with Android preserving the prior-prompt fact across process recreation; `android_services_smoke` verifies Android Photo Picker and SAF selection, bounded byte reads, and release on the AVD | other service-kind picker adapters; lock/unlock, surface-loss, low-memory/process restoration, and physical iOS/Android lifecycle, IME, and accessibility runs |
| UI-05 | implemented-tested (portable text/input; native gesture/device acceptance partial) | key/text/IME/focus/secure policy; `secure_history_test` and `widget_reentrancy_test` cover secure undo exclusion and in-flight scrub; `UiShortcuts` and `shortcuts_test` verify OS/app/menu same-chord precedence and focused-control priority; word navigation; `widget_layout_geometry_test` verifies Tab/Shift-Tab order matches semantic order and skips hidden/disabled controls; `text_lifecycle_workflow_test` covers typed-handle editing, stale async validation, resource relayout, blur, teardown, and Chinese IME composition; retained/legacy selection offsets are UTF-8 bytes, handle and AppKit/UIKit ranges UTF-16, SDL/C IME ranges scalar counts, with surrogate and grapheme normalization covered by `widget_handles_test`; `widget_layout_text_test` covers combining/ZWJ editing, mixed Hebrew selection, and multiline clipboard paste; `widget_layout_diagnostic_underline_test` verifies independent UTF-16 editor diagnostics and IME composition decorations; `sdl3_text_test` covers Japanese IME; the 1,187-row Unicode 15.1.0 corpus passes; Android AVD gate verifies composing-run replacement, committed `你好👋`, and accepted 336.38-point visible / zero hidden IME insets through the UTF-16 API; WasmBrowser `key-code.alt` is mapped through hosted input | native contact-to-gesture adapter mapping (including stylus distinction), physical-device IME/accessibility paths, platform keymap fixtures declined by current Stage1 codegen, and remaining backend-specific text differences require separate acceptance |
| UI-06 | implemented-tested (partial native collection mapping and privacy adapters) | `UiCore` semantics incl. Image/Group/List/Status/Alert and typed collection count/position; `accessibility_metadata_test`, `accessibility_geometry_test`; `UiHandles::set_accessibility_sensitive` scrubs retained semantic nodes and inspector output, with `widget_inspector_test` covering immediate and fresh-frame redaction; virtual-row providers can mark `Item.sensitive`, covered by `virtual_accessibility_provider_test`; `UiVirtualAccessibility::Provider` validates and snapshots app-owned off-screen row metadata, while `ActivateProvider` routes logical activation with epoch checks; AppKit graph bridge exposes full logical list count plus realized visible row proxies and now publishes ordinary parent/child groups in the same transaction; `appkit_canvas_bridge_test` covers nested groups and transactional rejection; UIKit commits only semantic roots, preserves bounded ordinary parent/child traversal, and implements lazy `UIAccessibilityContainer` count/index/element callbacks with Elisa-owned provider lookup, anchored reveal and bounded proxy identities; `uikit_virtual_accessibility_test` and `uikit_accessibility_hierarchy_test` cover nested lookup, a million-row Unicode query, identity reuse, eviction, activation and teardown; Android Canvas serializes retained semantics to virtual nodes and queues actions back to the owner thread, with 11 host parser assertions plus Java/JNI/entrypoint compilation ([2026-10-03 evidence](validation-2026-10-03.md)); Android native-controls redacts through a generic node and suppresses text events, selection/range and copy/cut; UIKit native-controls applies a generic label/empty accessibility value, suppresses help/placeholder and denies text-field Copy/Cut, with state-transition coverage and simulator/device Showcase builds; AppKit native controls redact accessibility values for labels, fields, buttons, sliders and progress indicators, suppress help/prompts, and deny sensitive-field Copy/Cut/pasteboard export while preserving visible/model state; GTK applies generic labels, omits help/placeholders and masks range/check attributes; on GTK 4.14+, marked-sensitive entries expose empty `GtkAccessibleText` content/caret/selection/geometry while retaining editable state, tested on macOS GTK 4.24 and Linux GTK 4.22 under Xvfb; live Orca acceptance remains open. Win32 applies HWND UIA/MSAA annotations, help suppression and WM_COPY/WM_CUT blocking, with PE32+ cross-link evidence only ([2026-10-04 evidence](validation-2026-10-04.md)) | live Orca/VoiceOver/Accessibility Inspector/TalkBack acceptance, Win32 runtime/Narrator and edit TextPattern behavior, screenshot/export-trace redaction, and physical hosted-device runs remain unverified |
| UI-07 | implemented-tested (partial) | sizer/layout corpus, `UiConstraints`, `UiTheme`, `UiLocalization`, `UiValidation`, `UiIdentity`, `UiVirtualList` geometry and bounded realization; `UiInspector::Node.constraints` reports per-axis min/preferred/max facts, contradictions, low/high allocation clamps, and overflow policy (`widget_inspector_test`); `UiFlat` retains declared/effective preferred sizes and derives container preferences (`widget_preferred_size_test`); `UiConst::OverflowBehavior` preserves legacy compression by default and adds minimum-preserving `Clip`/`Visible` underflow policies consistent across paint, hit testing and semantics (`widget_layout_overflow_test`, geometry and scroll regressions); retained layout now explicitly preserves fractional logical frames without per-child snapping, with paint/hit/accessibility agreement checked by `widget_layout_rounding_test`; generation-keyed `UiResources::set_intrinsic_size` metadata supplies automatic preferred image dimensions and survives retries without leaking across generations (`widget_intrinsic_image_size_test`, `resource_state_test`); virtual list geometry, variable metrics, semantics, scroll, focus, and the million-item Showcase remain as previously validated | pixel-identical cross-backend rounding and broader overflow acceptance; AppKit physical off-screen focus traversal; UIKit device screen-reader/native scroll transaction; hosted collection mapping; budgets on other reference devices |
| UI-08 | implemented-elisa-boundary (host smoke passes; end-to-end assets partial) | `UiResources` state machine and `UiResourcePresentation`; `resource_presentation_test` validates accessible status copy and typed owner-checked Cancel/Retry actions, including stale-generation rejection; `UiResourceComponent` composes a reserved content well, generation-keyed Ready image, status/progress/recovery controls, accessible semantics, and owner-scoped viewport demand (`set_visibility_demand` never fetches; retry/rebind transfers priority; Ready/non-retryable states clear hints); `resource_component_test` covers intrinsic geometry, loading fallback, ready identity, offline retry, terminal corruption, stale generations, owner-isolated cancellation, owner-specific demand clearing and transfer, plus a bound host-operation token advancing download/decode/upload independently through retained refresh to the exact Ready image generation; Hello uses this component in its actual retained tree, routes Retry through its typed action, publishes visible demand, and rebinds replacement generations; its long content is hosted in a vertical scroll viewport, and `showcase_workflow_test` verifies the reserved 180×48 well, fallback pixels, progress visibility, stale-image removal, demand lifecycle, and desktop/phone behavior; generation-safe `UiResourceOperations` associates typed resource handles with host operation IDs, independent monotonic network/decode/upload progress, completion/failure, cancellation, forget, and stale-generation rejection; `resource_state_test`, `resource_presentation_test` (including explicit offline fallback/retry), `text_lifecycle_workflow_test` (font-ready metrics reflow preserves selection, IME composition, and focus), `resource_operations_test`, and `UiHarness` deterministic operation injection cover the UI boundary; SDL3 upload advances `Ready` only after successful texture update and settles its UI operation association (`sdl3_image_upload_state_test`), with renderer-recreation pixel coverage; Skia's `complete_uploaded_image` publishes a decoded/uploaded generation and settles its UI operation association (`skia_image_upload_state_test`); AppKit and UIKit `complete_uploaded_image` adapters bind host-owned CGImages by resource slot/generation and settle upload; both fixtures now allow only idempotent live bindings and require exact teardown before changing generation or native object (`scripts/check_appkit_canvas_image_upload.sh`, `scripts/check_uikit_image_upload.sh`, lifecycle policy only); the current-source resource-profile guest passes `check_wapp_resources_ui.sh` through the WasmBrowser runtime and updates `UiResources` from a host asset operation; the UIKit simulator/device app+ABI gate now passes | real installed-package chunk graph, production host decode wiring, native device/pixel acceptance; unified hosted window+resource composition remains unverified |
| UI-09 | implemented-elisa-boundary (host activation/dispatch smoke passes; SDK-hosted app partial) | `UiFeatureView` coalesced owner leases, per-owner cancellation/disposal, token-safe deactivation tombstones, stale polling, retry generations, tokenless typed host-rejection transition, and bounded activation-token-checked content snapshots (UTF-8 title/body/action key) in `feature_view_test`; `UiFeaturePresentation` maps states to accessible status/alert records, paint tones, semantics, and owner-scoped recovery actions; `UiFeatureComponent` builds the parent-owned retained screen and captures the content sequence/action key it rendered; `content_action_key` fails closed when a newer snapshot is published before refresh, preventing stale labels from dispatching unseen actions; refresh adopts the next copied label/key pair together; status semantics and owner release on cancel/dismiss; `feature_component_test` covers co-owner cancellation, retry generations, live-token tombstones, ready-feature dismissal, and host acknowledgement; `feature_sdk_composition.elisa` drives loading→ready and copied SDK content through one retained tree and verifies stale-action rejection/recovery; current-source `check_wapp_features_ui.sh` exercises content publication/readback in its WIT guest and requires acknowledged teardown; scoped Stage0/Stage1 struct-field shadow smoke passes | actual SDK-generated feature content through a production host adapter, live rendering of registered host surfaces, and physical accessibility/device acceptance |
| UI-10 | implemented-tested (partial) | `UiInspector` hierarchy/bounds/dirty/focus/semantics/timings; bounded `UiDiagnostics` source-linked records with sensitive-message redaction and inspector snapshots; opt-in retained-widget sensitivity redacts text/help and returned semantic records; `UiCore::diagnostic_command_*` and `UiPaint::replay_diagnostic` collapse secure or opted-in retained widgets to opaque masks without changing trusted rendering; `widget_diagnostic_redaction_test` and `painter_instance_test` cover the sanitized stream/replay; hosted typed diagnostic log events, deterministic `UiHarness`, release packaging, and per-build toolchain display | native-control screenshots/traces and platform-owned exporters must adopt the policy; compiler source-map correlation and native SDK log sinks remain |
| UI-11 | implemented-elisa-boundary | `UiRemote` negotiation/lifecycle/acknowledgement/limitations plus generation-bound, complete semantic-snapshot admission and acknowledgement in `test/remote_test.elisa`; the normal submission path now derives its count from the current `UiCore` semantic tree, exposes bounded current-node enumeration for adapters, and rejects overflow before acknowledgement; WasmBrowser/SDK now expose and smoke-test the independent bounded `accessibility@1` transport profile, and the hosted UI publishes a versioned bounded snapshot through the legacy window world with runtime validation | native presentation adapter and device accessibility inspection remain |
| UI-12 | implemented-tested (native C/C++/Rust/Go; component interop separate) | `elisa_ui.h` publishes `ELISA_UI_MAX_TEXT_BYTES`; the C host verifies the live fixed staging cap and embedded U+0000; C++17 header and header↔symbol checks pass; `capi_lifecycle_test` rejects callbacks after stop and `capi_widget_handle_test` covers the invalid sentinel and generation change; Go exposes the same cap, borrows a zero-allocation valid UTF-8 prefix from immutable strings, and `check_go.sh` runs prefix/rune-boundary/allocation unit tests plus a real linked host covering oversize text/IME, malformed suffix, embedded NUL, selection clamping, opaque widget validity, and UI-thread locking; Rust wrapper + example pass `check_rust.sh` | Cross-thread misuse remains caller-enforced by the single-UI-owner-thread contract; Go runtime OOM is not recoverably injectable (text dispatch itself does not allocate); no C/Go WIT component binding is claimed; duplicate release is not applicable because these bindings expose no owned releasable resource handle |
| UI-13 | implemented-tested (partial) | `UiBuild` version + compatibility; backend matrix; `run_tests.sh` requires `check_performance.sh`'s exact-tuple policy budget; required optimized real-Skia gate measures the public million-item Showcase workflow plus tail rendering over 21 samples, checks stable pixels, and enforces an exact host/compiler/Skia/source tuple in `test/showcase_skia_performance_budgets.json`; `test/performance_budgets.json` retains portable workload raw samples; `test/stress_test.elisa`; release packaging and guides; shell toolchain resolution now prefers explicit selection, then a development checkout, then an installed Elisa snapshot, with a no-sibling resolver smoke and real installed-snapshot C API build | clean-machine test against a released SDK-managed selection still needs a supported distribution/version policy; budgets on other reference devices, GPU upload, idle CPU, energy, and broader mobile-device performance remain |

UI-05 follow-up: native UIKit/Android cancellation now uses the additive
`PointerEvent.Cancel` contract, and mobile lifecycle loss clears gesture
contacts. Focused checks pass on the explicitly permitted stale Stage1 product;
[input evidence](../ui-events.md) records the scope and compiler hash. Native
identified-contact delivery is now implemented for UIKit and Android, with
bounded identity mapping and source preservation. Wire, mapper and UIKit host
callback tests and both native builds pass on the existing stale compiler.
The simulator HID gate also passes with the contact recognizer included in its
cancellation assertion. Android now queues reentrant callbacks with session
generation checks; host queue and production MotionEvent-transport tests pass.
Android package/export acceptance passes, but device execution is skipped with
no device attached.
Retained opt-in targets now receive captured drag/pinch/long-press/cancellation
callbacks; host tests cover bounds exit, hidden targets, legacy isolation and
direct contact ingress. Physical stylus/multitouch acceptance, kinetic touch
scroll and production zoom workflow verification remain open,
so the corresponding implementation-plan items remain unchecked.

Timing/capture follow-up: UIKit/Android now subtract the native stream origin
before narrowing timestamps, preserving gesture thresholds at long uptimes.
Production transport/clock host tests pass at 100-million-second uptime.
Deregistering and re-registering a retained target retires its old captures;
the UIKit host fixture verifies no stale long-press callback is delivered.
The simulator HID cancellation/tap/committed-text gate was rerun after the
native clock change and passes both tests. C/Go/Rust gates and source-size,
global-name and whitespace checks also pass on the existing stale compiler.
Lifecycle cancellation now reports the identity/position/duration of each
retained capture rather than reusing the recognizer's final global snapshot.
The UIKit host test captures a button and a text field separately, then proves
both cancellation callbacks report the contact belonging to their own target.
UIKit canvas secure-entry now queries the focused retained field and disables
native autocorrection, spell checking, smart quotes and smart dashes for secure
entry. Keyboard synchronization reloads native input views when privacy changes.
UIKit host regressions verify secure, nonsecure and no-focus traits; the
simulator app compiles. Device password-keyboard inspection and mobile purpose,
selection/context-action and scroll-to-focus acceptance remain open.
The UIKit host gate now verifies the active-keyboard native boundary too:
secure and normal transitions request one reload each, unchanged traits avoid
reload loops, and blur retires the keyboard without an extra reload. All checks
pass on the existing stale compiler; physical secure-keyboard inspection is
still separate and unverified.
Retained text fields now store normalized purpose behind a typed handle setter;
password purpose activates secure storage. UIKit canvas maps email/URL/number
and search to native keyboard/return hints and reloads on active purpose changes.
Host tests verify email/number query values, password hardening, native refresh
and rejection of nontext/invalid targets. Other mobile acceptance remains open.
Android canvas now applies retained purpose to EditorInfo via an atomic owner-
thread-published JNI snapshot, with secure suggestions/learning suppression and
input-connection restart on active purpose changes. The production Java trait
mapper host test passes against Android SDK constants, including unknown
purposes. Android package builds; actual device keyboard/restart verification
remains open.

UIKit selection geometry now returns a native single-line selection rectangle,
rejects invalid locations and normalizes RTL endpoint order. The text-protocol
fixture is included in the focused input gate; all 17 Elisa tests and Android
host gates pass together on the existing stale compiler. The simulator app
builds. Native-menu and trailing-handle simulator acceptance are recorded below;
native gesture interruption and physical-device acceptance remain open.

UIKit native menu follow-up: simulator HID long-press now presents the edit
menu and verifies Select All/replacement plus Copy/Cut/Paste. A native semantic
publication feedback loop was fixed: publishing accessibility values no longer
enters the assistive-edit setter and collapses retained selection/composition.
The menu schema and eligibility stay in Elisa; native actions capture the
original tree/field and reject retired, disabled or recycled documents. Native
gesture interruption, physical-device acceptance and non-Latin IME
workflows remain open. These results still use the stale compiler opt-in.
The native gate now requires nine passing XCUITests. Its secure-field test
confirms input receipt without publishing password contents/length and checks
Copy/Cut are absent even after Select All. The expanded clipboard test covers
native Copy, Cut-to-empty and Paste restoration. The fourth test drags a native
trailing handle and proves replacement affects only the selected prefix; all
nine tests pass together, including retained-selection-confirmed combining
cluster replacement preserving a complete ZWJ-family emoji, plus Hebrew RTL trailing-handle replacement
and leading-handle replacement in both LTR and Hebrew RTL. These preserve the
opposite suffix/prefix rather than merely moving a caret. Elisa owns endpoint anchoring and cancellation,
rejects changed text revisions or retired documents, and suppresses ordinary
pointer presses on handle contacts. Host tests cover leading/trailing adjustment,
cancel restoration, combining marks, text changes and focus/tree retirement.
The ninth native test verifies Unicode selection survives Home/reactivation in
the same process, handles and keyboard recover, and replacement preserves the
family emoji. This covers completed-drag background/resume, not interruption
during a drag, lock/unlock, process restoration or physical-device acceptance.

Android ingress follow-up: the actual composing/commit entry points now gate
editing on active lifecycle and a focused editor, and reject malformed counted
buffers before staging. `android_ime_ingress_test` covers provisional/Chinese
commit, focus/background/surface/stop rejection and staging scrubbing. The
18-test focused matrix and Android host gates pass; the production Showcase
entry compiles with unchanged IME exports. APK/device selection acceptance,
stale connection ownership and JNI-thread serialization remain open.

Native email-keyboard simulator acceptance passes: the smoke app selects Email
purpose and the XCUITest asserts the native @ key after switching from Name.
Both HID cancellation/tap and committed-text/purpose tests pass with zero
failures (28.568 seconds of assertions). Startup was delayed in CoreSimulator's
launch bridge; the same live run eventually completed without a restart.
This uses the existing stale compiler and does not prove physical-device
password, selection-handle or broader IME acceptance.

Mobile focus-reveal follow-up: viewport/inset relayout now reveals the focused
retained text field through scroll ancestors, and inner offset updates are
reflowed before outer comparisons. A typed explicit reveal API is available.
`mobile_focus_reveal_test` covers keyboard occlusion, user-scroll preservation
and minimal nested offsets; geometry/text-layout regressions pass. Device
caret/selection workflows and oversized multiline caret reveal remain open.
The full UIKit host surface/input/accessibility fixture also passes after the
focus-reveal changes. The previously observed compiler seed process has exited,
but the compiler toolchain check still rejects the installed product as older
than compiler sources; this does not establish fresh-compiler acceptance.

The first implementation batch (plan §21) is partially evidenced: the public
backend/API map consumes pinned SDK bindings, and the hello reference screen
covers persistence, text, and resource errors on native backends. The fresh
hosted build now produces a JS-free component package through the repaired
intrinsic/runtime path. Mobile execution proceeds through the iOS/Android
gates above.

UI-07 large-text follow-up: the flat retained painter now resolves each
widget's app-owned base font size against current `UiTheme.text_scale` in
measurement, paint and text-editing geometry. Labels remeasure, text fields
grow their minimum height, and restoring scale does not require rebuilding or
mutating the base style. `widget_text_scale_test` plus the text, theme, geometry
and scroll regressions pass. Showcase Forms now measures primary-action labels,
stacks the retained actions at narrow/large-text widths, resizes field minima,
and hides its one-line description when it cannot fit; the main Showcase page
is hosted in a scroll viewport. `widget_responsive_axis_test` and
`showcase_forms_responsive_test` pass, and the full Showcase entry fixture
compiles. Cross-backend reference-app acceptance with long translations,
keyboard insets and large text remains open.

UI-07 translated-action refinement: `ShowcaseForms` applies its small
English/German action-copy table when the locale revision changes, and
`adapt_to_width` measures those retained captions so locale changes reflow at
the same viewport width. `showcase_forms_responsive_test` verifies minimum
widths, stacked arrangement, stable button handles, and retained
text/selection/focus. Full catalog/device acceptance remains open.

UI-07 plural-message integration: `UiLocalization::PluralForms` and
`plural_message` select app-owned text by locale category with `Other`
fallback. `FormatBuffer`, `format_count`, and `format_plural` provide bounded
caller-owned decimal `{count}` substitution without retaining catalog or
output storage. `localization_test` passes on Stage1 and the 116-test aarch64
portable corpus; locale-specific digit/grouping rules and a full catalog
loader/formatter remain open.

UI-07 validation presentation: `UiValidationPresentation` maps revision-bound
validation state to visible/pending/error flags, typed tones, and accessible
Status/Alert roles. Its Label-only update path cannot mutate the field being
validated, and stale snapshots cannot overwrite a newer revision.
`validation_presentation_test` covers stale async completion, all presentation
states, semantic Alert publication, and preservation of text, selection, and
focus; live screen-reader announcement remains unverified.

2026-10-04 validation follow-up: the full UIKit HID suite now passes all nine
XCUITests after activation requests a redraw, including retained selection
survival across background/resume. The Metal viewport fixture passes its
dedicated macOS gate, and `check_core_linux.sh` compiles, links, and passes all
110 portable tests on aarch64 Linux after its native test-stub wiring was
aligned with the macOS runner. This does not replace a fresh full matrix run;
the latest broad run still has separate performance-budget, WasmBrowser SDK,
and pinned-Skia environment constraints documented in
[the focused validation follow-up](validation-2026-10-04.md).

UI-12 C ABI audit and native linking: `scripts/check_capi.sh` compares the
public host entrypoints and app callbacks against the generated Mach-O object
and shared-library symbol tables, in addition to header/source declarations.
It builds and runs the C host against both a static archive and a dylib; the
C++ header smoke also passes. Fresh `check_rust.sh` and `check_go.sh` runs pass
the downstream wrapper checks and linked examples. `docs/ui-bindings.md` now
states the ABI version, UTF-8/counting and borrow rules, invalid-input/no-status
behavior, opaque generation-scoped widget identity, and absence of
foreign-owned releasable resources. WASM component interop remains a separate
SDK contract and is not inferred from native C linking.

UI-12 control API increment: C, Rust, and Go can now compose rows/columns,
create counted-text labels, buttons, check boxes, radio buttons, sliders,
progress bars, and initial-value text fields; set captions and
enabled/visible/selected state; read/write selection and normalized range
values; request text-field focus and copy back a bounded UTF-8 value; activate
controls through synchronous widget callbacks; and invalidate tokens by
resetting the tree. The linked
examples exercise that lifecycle and reject wrong-kind/stale operations.
`capi_widget_handle_test` additionally verifies embedded-NUL text, malformed
and oversized UTF-8 prefixes, null-pointer rejection without mutation,
fixed-arena exhaustion, repeat teardown, stale-action rejection, selection
queries, UTF-8-safe field copy-out, and value normalization. This remains a
subset of `UiHandles`; input editing/IME operations, scrolling, virtualization,
broader styling/interaction, and the remaining acceptance matrix are still
open.
