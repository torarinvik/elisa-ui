# Current validation

Part of the [elisa-ui implementation baseline](../implementation-baseline.md).

## Installed compiler snapshot selection (2026-09-30)

Shell build scripts now share `resolve_stage1_root.sh`: explicit
`ELISA_UI_STAGE1` wins, then the adjacent development checkout, then the full
snapshot installed by Elisa's `install_stage1.sh` at
`${ELISAC_PREFIX:-~/.elisac}/stage1`. `check_toolchain_resolution.sh` passes
with synthetic roots for all three paths, including the installed-only
no-sibling case. `check_toolchain.sh` recognizes the installer's `SNAPSHOT`
metadata, verifies product/runtime freshness against bundled sources, and
prints its revision, installation time, source, and hashes; because a snapshot
has no Git ancestry, the check states that limitation rather than pretending
to compare it with `origin/main`.

The real installed snapshot on this host (`b841e64b`, taken
`2026-09-27T17:02:42Z`) passes the strict toolchain freshness check and builds,
links, and runs the C API example through `scripts/check_capi.sh`. Its product
and runtime hashes are `f29eba5ec88287035e363ddfda2fd7eea6e810edb87da38b049f281639e86008`
and `725a800cf04a64dd3410cbbf09734f68736615505fd15f0d8986cd95c227bf6a`.
Git development checkouts retain the existing behind-`origin/main` check.
The unvalidated `.elisascript` ports are unchanged.

After license acceptance/Homebrew upgrade, explicit `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
and default `bash scripts/check_capi.sh` both pass the native C/C++ link path;
the explicit run used the installed snapshot. Wasm imports/compiler freshness are separate.

## Broad suite attempt (2026-09-30)

The latest `scripts/run_tests.sh` used `ELISA_UI_REQUIRE_REAL_SKIA=0`,
`ELISA_ALLOW_DIRTY_STAGE1=1`, Rustup stable, an isolated WasmBrowser Cargo target,
and Xcode 27. Toolchain resolution, UTF-8/16, global names, refinements, Unicode,
C/Rust/Go, AppKit base, both image-upload gates, Wapp profiles, and the repaired
exact-tuple performance gate (three processes, 21 samples per phase) passed.
Its source-size check initially flagged this note at 611 lines; it is now below
the limit, and standalone `check_source_sizes.sh` passes. Remaining declines: AppKit canvas
(`copy_accessibility_text`, `accessibility_identifier`, `application_menu_label`),
UIKit (`accessibility_identifier`, `percent_text`), Win32/GTK (`controls_text_action`),
and Android controls (`copy_native_text`/`view`). Core/GTK Linux, Android
canvas/IME, and real-Skia were skipped or disabled.

The focused AppKit/UIKit image-upload policy gates run before the broad backend
matrix and passed, including UIKit simulator-object compilation. The ordinary
test loop passed `accessibility_geometry_test` and
`accessibility_metadata_test`, then exited 2 at
`test/appkit_canvas_appearance_test.elisa` on the AppKit codegen declines above.
Later per-file fixtures were not reached. This remains a partial suite run, not
full acceptance.

`struct_field_refinement_shadow_smoke.sh` passes on Stage0/Stage1: invalid facts
remain rejected, block/assignment/loop/match shadows allow valid refined
returns, and the unrefined by-value parameter is diagnosed after its shadow closes; `check_refinements.sh` also passes on the current product. The current Stage0/Stage1 field-access parity smoke passes primitive-reference rejection and branch-local shadow cases.

## Retained-tree benchmark follow-up (2026-09-30)

Replacing global `UiHandles::invalid()` initializers with the equivalent `UI_HANDLES_INVALID_HANDLE` constant fixed the Stage1 benchmark fixture. The strict exact-tuple gate passes three processes and 21 samples per phase under the established M5 limits; its raw baseline is recorded in `test/performance_budgets.json`. The retained-harness fixture passes; UIKit virtual accessibility still hits the backend declines above.

## Full Unicode corpus generator repair (2026-09-30)

The generated corpus had constructed each row with the NUL-terminated `sview`
helper from a raw pointer. That mishandled the embedded-NUL row and made the
current Stage1 decline all generated row bodies. The generator now uses
`UiText::fixed_bytes_view_range` with each row's fixed-array extent. Against
fresh Stage1 product SHA-256
`4009dcef7c05ebfbeea3d8007801a3057968e2d2a381fa3d5c43e7d601265f02` and
runtime SHA-256 `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb`,
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ELISA_UI_STAGE1=../Elisa-compiler ELISA_ALLOW_DIRTY_STAGE1=1 bash scripts/check_unicode_conformance.sh`
passes all 1,187 rows from Unicode 15.1.0 (data SHA-256
`ed9c5e92fd0911ccbeeb63c97cb19c519ea272ff1112ce843abd991582dd848f`). This
focused pass does not imply the separate platform text/IME gates or the broad
`run_tests.sh` attempt are green.

## Bounded-view component runtime follow-up (2026-09-30)

A fresh Stage0 seed built Stage1 from compiler revision `9fa645b`. The product
SHA-256 is `4009dcef7c05ebfbeea3d8007801a3057968e2d2a381fa3d5c43e7d601265f02`
and runtime SHA-256 is `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb`.
The freestanding runtime now supplies `unsafe_sview_bounded_bytes`; Stage1
directly lowers `StringView{data, len}` to `{ptr, i64}`; Stage0/Stage1 smoke
passes with embedded NUL. The UI `check_wapp.sh` builds and inspects its
component; shared-target `wb-runtime` compilation stalled twice, even once
with matching Rustup `rustc` (8.27 CPU seconds over 4m41). A fresh isolated
Cargo target with stable passed full `check_wapp.sh` and current feature/resource
gates. Scripts bind `RUSTC` from `rustup which` because `rustup run stable cargo` found Homebrew `rustc`. Typed SDK/UI composition links/runs; Stage0/Stage1
field-shadow smoke passes with scope restoration. Driver acceptance:
BARE 5/6 (pass), WITH-STD 4/0 (known red). Composition joins `run_tests.sh`
when SDK sources exist; shared-target stall cause remains unknown.

## Reopened-module refinement scope follow-up (2026-09-30)

The broad-run refinement diagnostic was caused by reopened `extend` blocks
receiving distinct semantic scope IDs. The compiler now reuses a canonical
module scope for repeated `(parent, child-name)` paths and performs read-only
scope lookup when collecting refinement-argument laws. The new
`refinement_arg_reopened_module.elisa` regression reproduces a qualified call
from one `extend` block to a refined function declared in another; the
Stage0/Stage1 `refinement_arg_scope_collision_smoke.sh` passes, as does the UI
`check_refinements.sh` gate.

After reseeding from the dirty compiler checkout at HEAD
`54360bf68398b4da8d63b82a3ad2979667798aa2`, the Stage1 product SHA-256 is
`6d331655e11231d48a1bb73b86cf6743b58ea0a0d53add433f9c540c41ba2905`; runtime
object SHA-256 remains
`6a8d933dc5d9e77d491de34225ca21b7a37c117182e1e0e14d3a3e20ff6afc5e`.
The acceptance rerun was pinned to this exact product with
`ELISA_ALLOW_STALE_STAGE1=1`: BARE passes at 5 disagreements (limit 6), and
WITH-STD reports the same four known gaps—`affine_container_return.neg.elisa`
(accept-gap), plus `affine_spread_copy.neg.elisa`,
`darray_builtin_arity.neg.elisa`, and `darray_mutable_receiver.neg.elisa`
(reject-gaps). WITH-STD remains red against its zero-disagreement ratchet, but
the reopened-module change adds no new driver disagreement. An earlier run
overlapped a second Stage1 seed and produced 288 freshness-guard exit-2 cases;
those results are invalid and excluded.

A later source edit in compiler `src/backend/codegen_expression_type_place.elisa`
made the product stale. A fresh seed attempt failed in
`Backend.emit_contract_old_snapshots` because it could not infer region
parameter `__rg_runtime`; that concurrent `old(EXPR)` change was left intact.
The selected product remains SHA-256
`6d331655e11231d48a1bb73b86cf6743b58ea0a0d53add433f9c540c41ba2905`, but it
omitted that later edit at the time; the subsequent successful Stage0 seed is
recorded below. The earlier freshness-script invocation used a relative binary
path and skipped its check; an absolute-path invocation confirmed the stale
state. At that point, fresh hosted-profile reruns were blocked because the
WasmBrowser scripts set `ELISA_ALLOW_STALE_STAGE1=0` and rejected that product.
Earlier profile-gate passes remain evidence for the compiler product selected
at that time, not a rerun against the current source state.

## Fresh WasmBrowser profile runtime gates (2026-09-30)

Both UI-owned hosted profiles now pass their current-source runtime smoke gates. The UI checkout is HEAD `9487a79faba3ad9839abd22fdb526c60a32a2fed`; the
WasmBrowser host checkout is HEAD `125084c03287dc1f68e5211ed89aace818ff24aa`, and the SDK checkout is HEAD `fa832f0e812254b0edb0447a17078397911c3d01`. The
feature and resource WIT contracts have SHA-256 values `94769ab51e93bb8d4ddd08e31cda00e0b848ad7400fe1183ba23c7b1e06f7f16` and
`78dfec4584243b0b5ddb4434364e70adc29892c9013f8c4a428320e874a4dbd4`, respectively. The selected Stage1 compiler is still the intentionally dirty
`../Elisa-compiler` checkout at `54360bf68398b4da8d63b82a3ad2979667798aa2`, product SHA-256 `74a68250c6d4c3aea2184e5ad0e8f1c3357a4c292d4588a9629ce986100f5d31`,
and runtime object SHA-256 `6a8d933dc5d9e77d491de34225ca21b7a37c117182e1e0e14d3a3e20ff6afc5e`.

The WasmBrowser runtime and both validator examples pass `cargo check --locked -p wb-runtime --example validate_feature_component` with Rustup Cargo/rustc
1.98.0. The full gates also pass with that toolchain and an isolated Cargo target directory: `scripts/check_wapp_features_ui.sh` validates host activation,
feature registration, readiness/payload, command and callback dispatch, resource round-trip, and acknowledged teardown across the explicit WIT boundary;
`scripts/check_wapp_resources_ui.sh` validates that the asset operation updates the generation-safe `UiResources` lifecycle. On this host, set
`WASM_BROWSER_RUSTUP_TOOLCHAIN=stable` to select the known-good Rustup compiler for all Wapp gates (the default Homebrew Cargo build had stalled during dyld
dependency loading); `CARGO_TARGET_DIR` may be set to isolate its build cache. The feature component SHA-256 is
`6e61b02e27e4b4044e430c73917903f9a7196d158f520ed79e9439a8b5646f34`. `DEVELOPER_DIR=/Library/Developer/CommandLineTools` is required by the current native
compiler link environment. Cargo emitted existing dead-code warnings and Apple's linker emitted non-fatal “no platform load command” warnings for
Elisa-generated archive objects; both gates exited successfully.

The Homebrew Rust 1.98.1 build had remained in dyld dependency loading; the Rustup 1.98.0 toolchain completed the same checks without changing global toolchain
settings. `UI-08` still lacks installed-package chunk-graph, window+resource composition, and AppKit/UIKit native-image integration evidence. `UI-09` still
lacks the end-to-end SDK-hosted feature content/data surface; the focused host activation and dispatch boundary is now exercised.

## Export-global alias link follow-up (2026-09-29)

The Stage1 product selected by the UI scripts, from sibling compiler checkout `../Elisa-compiler` at HEAD `54360bf68398b4da8d63b82a3ad2979667798aa2`, passes
`assert_stage1_fresh.sh`. Its SHA-256 is `74a68250c6d4c3aea2184e5ad0e8f1c3357a4c292d4588a9629ce986100f5d31`; the runtime object SHA-256 is
`6a8d933dc5d9e77d491de34225ca21b7a37c117182e1e0e14d3a3e20ff6afc5e`. The backend native smoke passes all 543 compile-and-run checks, including the legitimate
exported-global alias and the regression that excludes `__lsp_decl_name` metadata from alias materialization. The same fresh product also passes
`struct_field_refinement_shadow_smoke.sh`: nested block, assignment, loop, and match shadows remain accepted, and the unrefined by-value parameter is diagnosed
again after its shadow scope closes.

`DEVELOPER_DIR=/Library/Developer/CommandLineTools` restores compiler linking without changing system settings. With that environment, the fresh UI feature
guest and runtime now link into a Wasm component; the prior duplicate `__lsp_decl_name` link failure is resolved. The prebuilt WasmBrowser validator accepts the
component structurally. The current-source validator rebuild, which exercises feature command/callback dispatch, stalled while compiling `wb-runtime` (over 12
minutes with about 9 seconds of compiler CPU time) and was interrupted. Thus fresh host dispatch validation remains unverified even though component generation
and structural validation pass.

## Named-type ownership and SDK composition follow-up (2026-09-29)

The sibling compiler at HEAD `54360bf68398b4da8d63b82a3ad2979667798aa2` was reseeded from its current dirty source tree after the linker repair. The fresh
Stage1 product SHA-256 is `ce7aca08276397ddcf03a20aa1390110a1df435aaa2f28eb5db68c7912d5c5d5`; its runtime object remains SHA-256
`1874b6e18782b211d1e5cd0520b12e82cf95b03b3674cc22a7921a98f37f12b0`. `assert_stage1_fresh.sh` passes. The non-fatal linker warning about the new SDK's
`libSystem.B.tbd` did not prevent either product from being written.

`test/parity/refined_alias_return_scope_smoke.sh` passes on Stage0 and Stage1. It covers a sibling module's same-named struct beside a root refined alias, the
root alias in an aggregate field used by nested fallible functions, and a negative control ensuring a module-local struct still rejects a primitive.
`struct_field_refinement_shadow_smoke.sh` and `refinement_arg_scope_collision_smoke.sh` also pass. The real `test/feature_sdk_composition.elisa` Stage1 compile
now emits a 4.7 MB LLVM module with no `!elisa.declined` marker; the earlier refined-return mismatch and `ready`/`advance` backend declines are gone.

The full `driver_acceptance_smoke.sh` remains partially red at the existing with-stdlib baseline: bare mode passes with 5 disagreements against a limit of 6,
and with-stdlib reports the same four previously recorded gaps (one `affine_container_return.neg.elisa` accept-gap plus reject-gaps in
`affine_spread_copy.neg.elisa`, `darray_builtin_arity.neg.elisa`, and `darray_mutable_receiver.neg.elisa`). No additional with-stdlib disagreement appeared.
This compile does not establish a fresh Wapp component link; the separate duplicate `__lsp_decl_name` component/runtime symbol issue remains.

## Post-restart validation (2026-09-29)

The Xcode license/Homebrew repair restored native linking: the Xcode-selected linker successfully built and ran `ui_harness_test`. The initially selected
sibling Stage1 product was revision `98261837ddc8ba0596c3bf9b0c5906475bf289b7`, SHA-256 `a10dafac0a9db4d751720ae2038718aacc39325d226aaca2125316f1405c7914`; its
runtime object was SHA-256 `741c2f6efd433ab6d92c7cadf275c8ceb92b3301eaf48a03a3f0cd89e0a1bd99`. Those initial UI runs explicitly allowed the then-current
compiler checkout without rebuilding it. A later targeted self-host was performed for field-return scope validation; its product and results are recorded below.

The source-size, unique-global-name, and refinement checks pass. The focused `widget_inspector_test` compiles, links, and passes with the bounded diagnostic
record API, including stale-record rejection after ring rotation and reset. The data-driven Unicode gate does not reach execution: Stage1 declines all 1,187
generated case bodies as `call expression` and emits no object.

The platform gates are not green with this product. AppKit canvas now gets past static aggregate initialization but Stage1 declines three bounded-view helper
bodies. Android native controls declines `copy_native_text` and the Showcase formatter view; UIKit declines its accessibility identifier and percentage value
helpers; Win32 and GTK each decline `controls_text_action`. These are backend code-generation failures, not successful package/device validation. The Wapp
source compilation reaches component linking, where the selected freestanding runtime lacks `env::unsafe_sview_bounded_bytes`; the component is not produced and
no hosted runtime smoke is claimed. The native toolchain repair does not resolve that separate component-runtime boundary.

## Field-return scope and UI-09 follow-up (2026-09-29)

The sibling compiler was reseeded from its current, intentionally dirty local source tree at HEAD `54360bf68398b4da8d63b82a3ad2979667798aa2`. The resulting
Stage1 product SHA-256 is `7c9c594d6f2956c3d4e0d542f87d93d26f4fb32236891306efd3ffd5cb3afe71`; its runtime object SHA-256 is
`1874b6e18782b211d1e5cd0520b12e82cf95b03b3674cc22a7921a98f37f12b0`. `assert_stage1_fresh.sh` accepts this product when the dirty-source override is explicit.

The scope-aware `check_field_return_refinement` change passes `test/parity/struct_field_refinement_shadow_smoke.sh`. Its Stage0-valid fixture covers by-value
parameter shadows from a local declaration, assignment, loop binder, and match alias without a false return-refinement warning. A paired control confirms the
original unrefined by-value parameter is visible again after the inner scope and receives the expected warning. `feature_presentation_test` also compiled,
linked, and ran with this exact product (`feature presentation: all checks passed`).

The broader `driver_acceptance_smoke.sh` is not fully green on this dirty compiler state: bare mode passes its ratchet at 5 disagreements (limit 6), but
with-stdlib mode fails at 4 disagreements (limit 0): `affine_container_return.neg.elisa` (accept-gap), and `affine_spread_copy.neg.elisa`,
`darray_builtin_arity.neg.elisa`, and `darray_mutable_receiver.neg.elisa` (reject-gaps). These are distinct from the focused field-return fixture; because the
compiler tree contains other local parser/semantic changes, this run does not attribute the disagreements to the field-return change.

The latest `test/feature_sdk_composition.elisa` compile still fails before linking. The SDK `features.elisa:103` return expects `FeatureHandle |`
`FeatureWireError` but receives `u64`; six `is_valid` refinement-argument diagnostics remain in `ui_tasks.elisa`, `ui_handles_style.elisa`, and
`ui_handles_input.elisa`. A fresh `check_wapp_features_ui.sh` attempt also stops at Wasm linking because generated `__lsp_decl_name` is duplicated between the
component object and the rebuilt runtime object; no component or fresh host-runtime validation is claimed. `git diff --check` passes in both UI and compiler
checkouts.

## Qualified refinement-call scope follow-up (2026-09-29)

The sibling compiler was reseeded after the module-aware refinement-argument scope change. The fresh Stage1 product SHA-256 is
`49ea4a9b0a5727e5a935a6b2cb35afb347f0b22e62f535e657e9c4d246fb3ffe`; the runtime object remains SHA-256
`1874b6e18782b211d1e5cd0520b12e82cf95b03b3674cc22a7921a98f37f12b0`. The product passes `assert_stage1_fresh.sh`.

The new `test/parity/refinement_arg_scope_collision_smoke.sh` passes with this product. Stage0 and Stage1 each report exactly the expected unproven argument for
explicitly qualified `Feature::is_valid(value)` and nested `Container::Feature::is_valid_nested(value)`; neither reports a refinement warning for the unrelated
unqualified same-name calls in `Widgets` modules. The existing `struct_field_refinement_shadow_smoke.sh` also passes, and `feature_presentation_test` compiles,
links, and runs (`feature presentation: all checks passed`).

A fresh compile of `test/feature_sdk_composition.elisa` no longer emits the six UI `is_valid` refinement-argument diagnostics. It still stops at the separate
SDK return mismatch in `wasmbrowser/features.elisa:103` (`FeatureHandle | FeatureWireError` expected, `u64` received). The previously recorded fresh Wapp
component/runtime duplicate `__lsp_decl_name` link failure remains separate.

`driver_acceptance_smoke.sh` was rerun on this product: bare mode passes its ratchet at 5 disagreements (limit 6), while with-stdlib mode fails at 4
disagreements (limit 0): `affine_container_return.neg.elisa` (accept-gap), `affine_spread_copy.neg.elisa`, `darray_builtin_arity.neg.elisa`, and
`darray_mutable_receiver.neg.elisa` (reject-gaps). The compiler checkout still contains unrelated local parser/semantic edits, so these corpus disagreements are
not attributed to the scope change.

## SDL3 image upload ownership (2026-09-29)

The SDL3 RGBA32 binder now accepts a `Requested` resource only after download and decode reach 100%, then advances upload progress and publishes `Ready` only
after `SDL_UpdateTexture` succeeds, completing the matching host-operation association when one is bound. Invalid or pre-decode attempts leave both the resource
and operation requested; an already-ready image can be rebound after renderer recreation. `test/sdl3_image_upload_state_test.elisa` compiles the image module
without the wider SDL host loop and passes its dummy-driver checks for readiness and bound-operation cleanup, then destroys/recreates the renderer, rebinds the
same ready logical image, draws it, and reads back the expected pixel.

The fixture compiled and passed with matching Stage1/runtime revision `074407d80372eea2539cf310b37c9ca1fce99661` (product SHA-256
`6ee6fce9a4b794be44f96c3b50c222e327cca90e6d849d3f3a1e197fb092de0f`, runtime SHA-256 `741c2f6efd433ab6d92c7cadf275c8ceb92b3301eaf48a03a3f0cd89e0a1bd99`). It also
linked and ran with Xcode 27 explicitly selected, confirming that the license/Homebrew repair restored the Xcode SDK/link path for this fixture. The newer
selected Stage1 product emits an object for this isolated source but its link against the current runtime stops on 46 duplicate compiler-generated
`___lsp_decl_name*` symbols. The full `sdl3_image_binding_test` still cannot emit an object with that product because the larger SDL include graph reaches the
existing `bounded_title`/`bounded_view` backend declines; this focused result is not represented as a full SDL backend or suite pass.

## SDL3 live font replacement (2026-09-29)

SDL3 now closes cached `TTF_Font` handles when its override changes, publishes font generations when an override changes or fallback discovery finds a face, and
resets `UiTextMetrics` while invalidating retained layout, paint, and semantics. Override paths are copied into a bounded SDL-owned buffer so lazy font opens do
not retain a caller's temporary `cstr`. `sdl3_text_test` adds a warm-cache replacement and label-reflow regression; the focused `sdl3_font_generation_test` also
mutates its caller buffer after setting a valid override and verifies that the copied path still opens.

The full `sdl3_text_test` still does not emit an object with the selected Stage1 product (SHA-256
`792e163e372ca659a9fcea5a0eb63a7e96dc59e013316eca02936ea7a8eba7b2`): after the local unsafe-effect grants and optional-renderer guards, its backend declines
existing `bounded_title` and `bounded_view` bodies as `call expression`. The isolated font-generation fixture does compile with that product when the
stale-product override is explicit, but linking its object against the matching runtime (SHA-256
`85c5e9763d71383d8dff539ff188ce80451abeeb1bb5cda6bf72eb63a2e548c1`) fails on 46 duplicate compiler-generated `___lsp_decl_name*` symbols.

The updated isolated fixture compiled, linked, and passed natively with a matching older Stage1/runtime tuple: compiler worktree revision
`074407d80372eea2539cf310b37c9ca1fce99661`, product SHA-256 `6ee6fce9a4b794be44f96c3b50c222e327cca90e6d849d3f3a1e197fb092de0f`, runtime SHA-256
`741c2f6efd433ab6d92c7cadf275c8ceb92b3301eaf48a03a3f0cd89e0a1bd99`. Its output was `sdl3 font generation: all checks passed`. This is real SDL_ttf behavioral
evidence for the isolated font owner, not a passing full-backend gate or a validation result for the current compiler/runtime pair. The source-size,
unique-global-name, refinement, and whitespace checks pass.

## Compiler semantic-scope validation (2026-09-18)

The sibling compiler is clean on `main` at `debbf68b`. Its fresh stage1 product has SHA-256 `1cbd19f6352bd0339e31ba61c2c9c900c3318309d1e079452bcbb9a4f15ab259`
and its runtime object has SHA-256 `1dbb59736ed498f8e602003e9504953e6f2a8bef916340882d3d4ce6df3e9e48`. The field-access-on-primitive checker now scopes local
type facts across branches, blocks, loops, lambdas, comprehensions, and match binders. Its regression fixtures cover both `mutable u8&.count` rejection and a
same-named inner `i64` shadow that must not make an outer `Point.x` access fail.

The current stage0 semantic probe reports the two intended positive findings and no negative finding. The stage1 parse-report probe reports `P 0`, two positive
findings, and `D 0` for the negative fixture. The required driver acceptance smoke also passes in both configurations:

```text
driver acceptance [bare] OK: 6 disagreements (ratchet 6) — 0 accept-gap, 6 reject-gap
driver acceptance [withstd] OK: 0 disagreements (ratchet 0) — 0 accept-gap, 0 reject-gap
```

The macOS 27 retained-tree performance run is now pinned in `test/performance_budgets.json` under the exact compiler/runtime/host tuple;
`scripts/check_performance.sh` passes with the recorded 21-sample budget. The AppKit headless gate also passes on macOS 27. Its tree assertion deliberately
counts framework-owned container children only, because current `NSButton` instances may expose private AppKit subviews that are not elisa-ui children. The iOS
simulator gate now bounds CoreSimulator discovery queries and reports a skip when `simctl` is unavailable or hangs during service startup; it does not turn a
missing simulator runtime into a passing device execution result.

## UI resource/feature boundary follow-up (2026-09-18)

The generation-safe `UiResourceOperations` association is now exercised through deterministic `UiHarness` bind/poll/complete/cancel/forget helpers, and
`UiFeatureView` carries a bounded activation-token-checked typed payload for a ready optional feature. The full non-Skia matrix was run with
`ELISA_ALLOW_DIRTY_STAGE1=1 ELISA_UI_REQUIRE_REAL_SKIA=0` and exited `0`, including the hosted Wapp build/runtime smoke and all Elisa tests. The run reported
only the documented iOS simulator/device and Android Skia/device skips; source-size, global-name, and whitespace checks also passed.

## Local toolchain and focused validation (2026-09-28)

The Xcode license was accepted and Homebrew was upgraded. The original link failure is resolved: with Xcode explicitly selected
(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, macOS 27.0 SDK), `test/ui_harness_test.elisa` compiled, linked, and ran with
`ui harness: all checks passed`. The Command Line Tools override is not needed for that focused executable.

The follow-up also replaces remaining raw counted-view constructions in the state/dialog accessors and uses bounded array-view helpers at the test seams. Using
the existing Stage1 product from sibling revision `98261837` with `ELISA_ALLOW_STALE_STAGE1=1`, these fixtures compiled, linked, and passed: `ui_harness_test`,
`widget_handles_test`, `widget_layout_text_test`, `resource_operations_test`, `resource_state_test`, `feature_view_test`, and `wasmbrowser_dispatch_test`.
`check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh`, and `git diff --check` also passed with that product (the compiler-source freshness
override was explicit).

Further focused runs with the same stale Stage1 product passed for `dialog_test`, `validation_test`, `localization_test`, `text_layout_test`, `event_wire_test`,
`unicode_conformance_test`, `ui_state_test`, `text_metrics_cache_test`, `virtual_accessibility_provider_test`, `accessibility_metadata_test`, `gestures_test`,
and `capi_app_text_test`. The source-size, global-name, refinement, and whitespace checks were rerun and passed after these edits. `controls_test` remains
unverified: its operation arena initializer now gets past Stage1, but the stale product declines the generic backend `apply` body before it can emit a linkable
unit. Equivalent explicit-`if` syntax did not change that result and was discarded. This is not a passing test and is not yet attributed to current compiler
sources.

The sibling compiler checkout has newer local parser/semantic sources than its Stage1 product, and those sources continued changing during this follow-up. A
focused temporary probe was accepted by Stage0 but rejected by the existing Stage1 product when a refined by-value parameter is used after a nested local with
the same name leaves scope. This indicates a likely conservative-fact restoration false positive in that product; it is not yet attributed to the newer compiler
sources. No fresh self-host or `driver_acceptance_smoke` result is claimed. Rebuild and rerun the parity gate only after the sibling compiler source tree
settles; any field-through-reference refinement change must pass that gate.

## Latest local follow-up (2026-09-17)

The shared `Elisa-compiler` checkout advanced with intentional local compiler fixes after the clean `5329edfd` baseline below. A fresh stage1 self-host from
that source produced product SHA-256 `5c77c7d86f26f19a43edb21502bbf3146d901c6453e172f5d0d99df423a4aba4` with the same runtime and Skia pin. The required
headless Skia painter, Showcase workflow, exact-tuple renderer budget, generic performance budget, and focused AppKit-Skia gate all passed; the current Showcase
run retained the stable tail digest `1ac21e37972207bb` and measured 14.512 ms median/17.024 ms maximum, within the 50/80 ms policy limits. The deferred-text
cleanup now scrubs the complete fixed arena, independent of queue metadata. The generic retained benchmark remains covered by the exact current tuple. Because
the sibling compiler working tree is intentionally dirty, these local checks use `ELISA_ALLOW_DIRTY_STAGE1=1`; the exact host/compiler/Skia/source tuples are
recorded in both performance manifests rather than silently inheriting the clean baseline.

## Latest compiler and renderer evidence (2026-09-17)

The 2026-09-17 follow-up fixes Elisa-owned RTL horizontal scrollbar paging: the painted thumb, hit-test geometry, and page delta now share the same direction
transform. `test/widget_layout_scroll_test.elisa` covers a physical track click away from the mirrored thumb as well as drag behavior. The fix is committed as
`0bba021`; its required real-Skia source bundle is `85c9f05ff5532e0bd43273aec8e2f0dfce6f21d3db6301ddf2251cd7a586957f`. The gates were rebuilt with the latest
local compiler product at revision `bfedb0d707a00797ddd16341f21a8b6e0a9677af` (product SHA `a73be5e165b9a53b4b69495d006f24b719a9749182d6e57b5e92958e8ce28f36`,
runtime SHA `dbed0552a85df51da0c050e4f009bb7c565f792a0676df0f465e9e986e8845a4`). The sibling checkout contains intentional local compiler edits, so this
follow-up used `ELISA_ALLOW_DIRTY_STAGE1=1`; the exact tuples are recorded in the performance manifests and passed the required gates. The current retained
benchmark measured a 1.824 ms median batch (3.898 ms maximum), while the current real-Skia Showcase workflow measured an 11.512 ms median (12.186 ms maximum);
both retained stable tail digest `1ac21e37972207bb`.

The preceding framework source revision was `d880c20` (with the preceding caret, WasmBrowser, renderer-budget, and validation-document commits `8342287`,
`ff65837`, `b68a10c`, `b5ec623`, and `5d6c3e8`). Its variable-height list cache uses deterministic least-recently-updated eviction at the fixed 256-entry limit,
typed handles expose a versioned snapshot/restore path, and the direct Skia text ABI rejects malformed or oversized UTF-8 before measurement or draw; the
retained text-field caret keeps its public rectangle-origin contract while painting the exact one-point rectangle; sealed hierarchy roots now support
Elisa-owned overlay grouping with a shared scrim and modal hit floor; `test/virtual_list_variable_test.elisa`, `test/widget_handles_test.elisa`,
`test/widget_layout_text_test.elisa`, `test/widget_caret_alignment_test.elisa`, and the real Skia off-screen host `test/hierarchy_overlay_test.elisa` cover
these boundaries.

The fetched upstream `main` is `45cb0ded70e7e8c8a41d21c63a09939706322ca4`. The shared compiler checkout is clean on `main` at
`5329edfdbefa27b5c1c51253da0073256ed51058` (ahead=11, behind=0 versus the fetched `origin/main`). Framework gates use this latest local build.

The latest clean stage1 used for the current gates is `../Elisa-compiler/bin/elisac-stage1`, revision `5329edfdbefa27b5c1c51253da0073256ed51058`. Its stage1
SHA-256 is `03fb7200424b6849ea3243c33e774270b4e8909a080136d05092251254b52024` and its runtime SHA-256 is
`85f1107eef00a7dd903e511df366b8b6cade4d8573cf0478f1de91604ea5beb9`. The product and runtime were freshly self-hosted from the current stage0 and the strict
`ELISA_UI_REQUIRE_CURRENT_STAGE1=1` toolchain check passes.

The pinned Skia checkout is revision `9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; `out/elisa/libskia.a` has SHA-256
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`. The clean upstream-main, c605, ce9e, 4cf3, 0f08, 8d7, 45cb, d6a, 8617, and latest 5329
compiler products have separate exact performance tuples recorded in `test/showcase_skia_performance_budgets.json`.

With the clean latest compiler and pinned Skia, the following headless gates passed without opening or foregrounding a window:

```text
ELISA_UI_STAGE1=../Elisa-compiler \
bash scripts/check_appkit_canvas.sh
  -O2 AppKit canvas build, fresh-process PNG, accessibility bridge,
  callbacks, ordinary nested hierarchy, bundle and signature: PASS
  fresh-process PNG sha256=
  fe983e37bd348cf130b6e8aa0c09aee733f934c6866df0de362d04e34a8da880

ELISA_UI_STAGE1=../Elisa-compiler \
bash scripts/check_capi.sh
  C header/Elisa symbol agreement and C example: PASS

ELISA_UI_STAGE1=../Elisa-compiler \
bash scripts/check_go.sh
  Go/cgo binding, real Elisa adapter, callback/text/viewport example: PASS

ELISA_UI_STAGE1=../Elisa-compiler \
bash scripts/check_uikit.sh
  UIKit SDK syntax, ABI, off-screen frame and semantic boundary: PASS

`test/uikit_virtual_accessibility_test.elisa` (compiled and linked with the
same latest stage1/runtime and `test/uikit_host_stubs.c`): headless UIKit
virtual-container provider, million-row reveal, bounded proxy identities,
activation and teardown: PASS

`test/uikit_accessibility_hierarchy_test.elisa` (same latest stage1/runtime and
stubs): nested ordinary parent/child lookup, root-only publication, invalid
index handling and teardown: PASS

`ELISA_UI_STAGE1=../Elisa-compiler bash
scripts/check_android_controls.sh showcase` builds the real Android
`android.widget` controls APK, verifies the distinct Elisa/JNI entry points,
absence of Skia/shared C++ dependencies, Java code and 16 KB alignment, and
reports the device half separately when no device is attached: PASS (package
half; device half skipped because no Android device was attached).

ELISA_UI_STAGE1=../Elisa-compiler \
SKIA_ROOT=/private/tmp/elisa-skia-check-20260914 \
bash scripts/check_skia.sh
  CPU-raster painter, off-screen pixels, fresh-process replay, Showcase pages,
  deferred resource replacement and state variants: PASS
```

`check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh`, and `check_unicode_conformance.sh` also pass with this compiler. The Unicode gate
executes the pinned UAX #29 15.1.0 corpus (1,187 rows).

The full real-Skia Showcase path reached its required exact-tuple benchmark with the clean latest 5329edfd product after the target-machine optimization level,
exact-rectangle caret, WasmBrowser lifecycle, and sealed-hierarchy overlay changes. Three fresh processes produced 21 tail-pixel-stable samples, with a recorded
median of 20.013 ms and a maximum of 23.934 ms, inside the current 50/80 ms policy limits. The exact source-bundle tuple is recorded in
`test/showcase_skia_performance_budgets.json`; a different compiler, source bundle, or host must add its own measured reference instead of inheriting this
result.

The complete `ELISA_UI_REQUIRE_REAL_SKIA=0 ELISA_UI_SIMCTL_QUERY_TIMEOUT=1 bash scripts/run_tests.sh` run passes every local compiler, renderer, native,
mobile-simulator, cross-target, Unicode, and portable fixture; that earlier broad run skipped Android canvas/device checks. On 2026-10-01, with pinned Skia
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`, NDK 30.0.16138531, and the Pixel_9 Android 37.1 AVD, `check_android.sh showcase` built/installed the ARM64 APK and painted portrait 1080x2424 (`status=1`, 1,023 colors, 288 ms), then passed lifecycle rotation/repaint at landscape 2282x1080 (system-bar constrained) and back to portrait. HOME/background and foreground/resume were accepted and a fresh portrait frame followed. `check_android_ime.sh` passed the real soft-keyboard path: composing-run replacement and commit of `你好👋`, then an accepted 336.38-point visible IME inset and accepted zero/hidden inset after Back; a second Back crossed the shared `UiBack` policy as unhandled and returned the root Activity to Android. The surface stayed 1080x2424 during the IME check. This read-only AVD has a built-in hardware keyboard, so `show_ime_with_hard_keyboard=1` was set only for that test session. Both Android gates used Stage1 product SHA-256 `c9120725bde202e70ea9ff94c9b87ab2026770eb5b29e95bfc1bc285f76eb9cf` and runtime `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb`; the dirty compiler checkout was at HEAD `d8b5d30` and reported no stale product. `check_android_controls.sh showcase` still declines `copy_native_text@5551` on this product; lock/unlock, surface loss, low-memory/process restoration, and physical-device acceptance remain unverified.

The hosted Wapp package builds, inspects, and passes its JS-free contract checks, and its WasmBrowser Rust smoke now passes through guest `start`, frame,
keyboard, pointer, and lifecycle driving. The fix aligned the SDK's primary WIT contract with the runtime's current `pointer-kind` enum, including the appended
`cancel` case, and lets component-mode export scanning carry named scalar enum parameters as their canonical `i32` representation. The focused compiler
regression fixture and the hosted runtime gate both pass.

On macOS 27, CoreSimulator can remain responsive at the process level while `simctl` discovery never returns after an Xcode/SDK upgrade. The iOS simulator and
touch gates now bound every runtime, device-type, and device-list query through `scripts/simctl_query.sh`; an unavailable CoreSimulator installation is reported
as a skip instead of hanging the suite.

Variable-height retained lists also accept a synchronous application measurement provider. The provider can supply logical row extents before intrinsic
fallback. Typed handles expose a bounded, versioned measurement snapshot/restore path owned by Elisa, with full validation before cache replacement;
`test/widget_handles_test.elisa` covers provider replacement, cache invalidation, intrinsic fallback, enumeration, and persistence.

## Hosted open vertical-slice gate (2026-09-18)

The hosted open-vertical-slice gate now builds and inspects the component package successfully. The compiler-side fix corrected WebAssembly intrinsic overload
selection (`llvm.wasm.memory.grow.i32`/`size.i32`), and the freestanding component runtime now provides the compiler-emitted `ctx_string_views_eq` helper.
Resize and pointer lifecycle callbacks use the typed `UiCore::EventRecord` path so no unresolved `env::UiWasmBrowser.*` imports are emitted.

The previous failure was:

```text
declare i32 @llvm.wasm.memory.grow.i32.i32(i32, i32)
```

The expected intrinsic is `llvm.wasm.memory.grow.i32`. The repaired compiler and runtime are committed in the sibling `Elisa-compiler` checkout at `d7aead96`,
`56364e77`, `86172169`, and `5329edfd`; `scripts/check_wapp.sh` reports a JS-free component package with the expected imports/exports. The current runtime smoke
reaches the guest successfully after the SDK/runtime WIT alignment; it does not restore the old intrinsic/import failure.

The aligned SDK contract and adjacent regression validation was also rerun from the sibling `wasm-sdk` checkout. `test.wasmbrowser_contract_test`,
`test.wasmbrowser_sdk_regression_test`, and `test.wasmbrowser_sdk_cli_test` completed with 313 passing tests and 3 skips. The skips are deliberate: the
installed Homebrew Rust toolchain is `rustc 1.98.1`/Cargo `1.98.1`, while the Preview 2 command profile is locked to Rust/Cargo `1.98.0`. The preview2 JSON
report test now uses the same exact-profile predicate as the build test, so an unavailable locked profile is reported as skipped rather than as a misleading
validation failure. No SDK lock was relaxed.

## Optimized AppKit validation

`test/appkit_canvas_surface_test.elisa` now passes at `-O2` with the clean latest compiler. The compiler target-machine setup uses the same optimization level
as the IR pipeline instead of always lowering through LLVM at level 0; the change is committed in sibling `Elisa-compiler` revision `5329edfd`. This removes the
mixed O2/O0 lowering path that previously exposed arm64 aggregate ABI differences in retained replay. The AppKit Canvas and AppKit/Skia production callbacks
both pass their off-screen optimized checks.

## Lifecycle-reset cancellation retention (2026-09-29)

`UiResources::reset()` now invalidates resource generations while retaining bound host operations as cancellation tombstones until `forget_operation()`.
`UiFeatureView::reset()` releases owner leases and payloads but retains live activation tokens as ownerless cancelled tombstones; hosts can enumerate them with
`deactivation_at()` and acknowledge after stop/restart. The deterministic harness exposes both cleanup queues beyond the app lifecycle. Resource, feature, and
harness regressions pass, including repeated reset, late-completion rejection, and acknowledgement after stop.

The focused `resource_operations_test`, `resource_state_test`, `feature_view_test`, and `ui_harness_test` compiled, linked, and ran with Stage1 revision
`074407d80372eea2539cf310b37c9ca1fce99661` (product SHA-256 `6ee6fce9a4b794be44f96c3b50c222e327cca90e6d849d3f3a1e197fb092de0f`) and its matching runtime SHA-256
`741c2f6efd433ab6d92c7cadf275c8ceb92b3301eaf48a03a3f0cd89e0a1bd99`. Object emission explicitly used `ELISA_ALLOW_STALE_STAGE1=1`; linking used
`DEVELOPER_DIR=/Library/Developer/CommandLineTools`. Source-size, global-name, refinement, and whitespace checks pass. This focused run is not a full
`run_tests.sh` result and does not close the separate SDK/host resource or feature-component integration gaps.

The follow-on `UiOwnerLifecycle::dispose_owner()` coordinates task tokens, resource/feature leases, validation fields, services, dialog cancellation, and
navigation entries under one nonzero owner ID, returning a typed per-subsystem report. `owner_lifecycle_test` passes shared-owner preservation, exclusive
resource/feature acknowledgement, stale callback rejection, dialog-result retention, owner-zero no-op, and idempotence. The hello resource demo now disposes
only its own resource owner during initialization instead of globally resetting `UiResources`; `showcase_workflow_test` seeds a different owner and verifies it
survives both initial and repeated app initialization. That test also exercises the hello validation screen using the coordinator and compiled, linked, and
exited successfully with the same matched Stage1/runtime pair. This does not replace host-owned cancellation or physical app teardown.

## Toolchain report routing and offline presentation (2026-09-29)

Build, render, and Skia-check entrypoints now pass their resolved `ELISA_UI_STAGE1` path to `check_toolchain.sh`; direct build entrypoints that did not report a
toolchain now emit the documented report before compilation. The focused override check selected `darrrecv` revision `074407d80372eea2539cf310b37c9ca1fce99661`
and printed its product/runtime hashes, warning that the checkout is dirty and 13 commits behind upstream. `resource_presentation_test` compiled, linked, and
passed with that existing product, including offline progress suppression, no automatic retry, and a fresh retry generation with reset progress. After the
pasted terminal log's Xcode-license acceptance, the same object also linked and passed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Shell
syntax, source-size, global-name, and whitespace checks passed; the full UI test suite was not run.

`UiResources::request()` now admits only bounded relative virtual asset paths matching the SDK resource contract; absolute paths, traversal/dot/empty
components, URLs, drive prefixes, backslashes, and UTF-8 control characters cannot enter the resource coalescing table. A nested UTF-8 path remains valid.
`resource_state_test`, `resource_presentation_test`, `resource_operations_test`, and `ui_harness_test` all compiled, linked, and passed with the same existing
Stage1/runtime pair. This is still framework boundary evidence, not package-byte decoding or a hosted SDK composition pass.

## Skia upload publication (2026-09-29)

`UiSkia::complete_uploaded_image` accepts only a live `Requested` generation with a nonzero uploaded handle and complete download/decode progress. It retains
the generation-bound image before publishing `Ready`, settles the associated UI operation record when present, supports operation-free synchronous loads, and
rejects cancellation/stale completion. The focused `test/skia_image_upload_state_test.elisa` compiles, links, and passes with Stage1 revision
`074407d80372eea2539cf310b37c9ca1fce99661` and its matching runtime; it tests the actual Skia resource extension with a headless drawing stub, not a real Skia
raster upload.

The broader `scripts/check_skia.sh` was also attempted with that same selected toolchain and currently stops before producing its painter object: Stage1
declines `replay_deferred_command` (`call expression`). This is separate from the focused upload-state result and leaves real renderer verification pending.

## WasmBrowser resource profile with UI state (2026-09-29)

`test/wasmbrowser_resources_ui_guest.elisa` now compiles the production `UiResources` state machine into the SDK's versioned `wasmbrowser:resources@1` guest. It
binds the host operation to a logical `asset.txt` generation, accepts two independently allocated byte chunks (`he` and `llo`), releases each host-owned list
through the canonical allocator, and publishes `Ready` only after the host operation is forgotten successfully. The emitted component was built with the matched
Stage1/runtime at `elisa-compiler-worktrees/darrrecv` revision `074407d80372eea2539cf310b37c9ca1fce99661` and passed the existing WasmBrowser
`validate_resource_component` executable.

Two toolchain/build limitations remain distinct: the current shared `../Elisa-compiler` tuple fails this UI component link with duplicate `__lsp_decl_name`
definitions between the component object and runtime; and a fresh Cargo rebuild of the WasmBrowser validator fails its runtime-policy build on
`input_sequence_next` (`call expression`). The prebuilt validator was used for this run, so fresh validator compilation remains unverified. This exercises the
host chunk API against the deterministic validator asset, not a real installed-package chunk graph, a unified window+resource component, or image
decode/renderer upload.

## WasmBrowser feature profile with UI state (2026-09-29)

`test/wasmbrowser_features_ui_guest.elisa` compiles the production `UiFeatureView` state machine into a versioned `wasmbrowser:features@1` guest. The guest
attaches the host activation token, maps a successful host poll to `Ready`, publishes a bounded `feature:ready` payload, registers command, surface, callback,
and host-resource entries, round-trips a host resource, and acknowledges deactivation only after the host confirms shutdown. The component passes
`scripts/check_wapp_features_ui.sh` with Stage1/runtime revision `074407d80372eea2539cf310b37c9ca1fce99661` and the prebuilt `validate_feature_component`
executable. `feature_view_test` also passes after `is_ready()` was changed to use an explicit validity guard before indexing.

This smoke calls the versioned WIT host imports directly; it does not yet prove composition with the SDK's higher-level `FeatureActivation` model. Including
that model and `UiFeatureView` together currently makes Stage1 reject the SDK's refined `FeatureHandle` return, even though the stock SDK feature guest builds
standalone. The current shared compiler/runtime tuple separately still fails component linking on duplicate `__lsp_decl_name` symbols; the native Xcode-linker
repair does not affect that component-link failure. Thus this is verified host/UI lifecycle evidence, not a completed typed SDK adapter or feature-surface
presentation integration.

## Accessible optional-feature presentation (2026-09-29)

`UiFeaturePresentation` maps requested/loading/ready/offline/denied/incompatible/ failed/cancelled states to bounded user-facing status or alert content,
semantic roles and action targets, and a normalized tone-coded status surface. The presentation API accepts tree-generation-checked `UiHandles::Handle` values
and permits actionable semantics only when the target is a retained Button. `feature_presentation_test` builds a status/detail/Button loading card, checks that
its status node points to the typed Button identity, activates that control, and updates the retained copy/removes the cancel control on Ready. It also
exercises paint normalization and recovery outcomes. Loading cancellation releases only the initiating owner's lease, retries return the next feature
generation, and incompatible or corrupt packages ask the application to choose a version rather than automatically reactivating the same package. Final
unstarted-owner cancellation now releases its empty feature slot immediately; a live host token instead remains a cancelled tombstone until acknowledged.

`feature_presentation_test` and `feature_view_test` compiled, linked, and passed with the matching Stage1/runtime tuple at compiler worktree revision
`074407d80372eea2539cf310b37c9ca1fce99661` and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The tests cover accessible status/alert roles,
semantic action mapping, hostile geometry normalization, retained-tree/Button composition, shared-owner cancellation, token-safe deactivation, offline retry,
denied/incompatible/corrupt outcomes, and package-version selection. Source-size, global-name, shell-syntax, and whitespace checks pass. This is
presentation-policy coverage, not a composed application feature surface or SDK activation-model integration; the previously documented WasmBrowser and
toolchain limitations remain.

## Current-source typed feature content and compiler scope (2026-09-30)

Stage1 revision `3fa4a7e590c3ae5919b759a85dc8f1e105246c8b` is two commits ahead of `origin/main`; strict freshness passes with `ELISA_ALLOW_DIRTY_STAGE1=1`. Product SHA-256: `4b36ce5a7dcf4c448ee037dce4ec393b603ed90d15aa534a90ee3888be8e83fe`; runtime SHA-256: `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb`.
The compiler checkout remains intentionally dirty; this UI turn changed no compiler or SDK sources. C API and Go (`GOEXPERIMENT=cgocheck2`) gates pass with the default Xcode 27 linker, including counted U+0000 preservation, allocation-free Go UTF-8 prefix validation, and fresh `capi_lifecycle_test` / `capi_widget_handle_test` runs.
Against that product, `widget_layout_text_test`, `widget_layout_geometry_test`, `widget_handles_test`, `text_input_test`, `widget_inspector_test`, `widget_reentrancy_test`, `secure_history_test`, `text_lifecycle_workflow_test`, `sdl3_text_test`, and `shortcuts_test` freshly compile, link, and pass. The `widget_reentrancy_test` rerun used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ELISA_ALLOW_DIRTY_STAGE1=1 bash ../Elisa-compiler/scripts/elisac_stage1.sh -O0`, linked the recorded runtime with Xcode clang, and passed its new same-slot rebuild assertion: the old edit preserved the replacement text, focus, and empty history. Focus-order tests verify Tab/Shift-Tab aligns with accessibility order and skips hidden/disabled controls. `shortcuts_test` verifies same-chord OS-reserved-over-app and app-over-menu priority, plus focused-control precedence. Secure fields are excluded from undo/redo and enabling secure mode scrubs history; the re-entrant callback regression proves an active edit cannot refill a scrubbed slot. Range tests verify UTF-8 byte selection of a supplementary emoji, UTF-16 getters, mixed Hebrew selection, and grapheme-safe normalization. Editing tests cover combining/ZWJ sequences, Japanese and Chinese IME composition, and multiline clipboard paste through Ctrl-V; the 1,187-row Unicode 15.1 corpus passes. The unit contract and single-line paste policy are documented in `docs/ui-text-input.md`.
`struct_field_refinement_shadow_smoke.sh` passes on fresh Stage0/Stage1 binaries, including rejection of an unproven loop-shadow construction and restoration of by-value parameter facts after a shadow scope. SDL3 and AppKit-canvas keymap fixtures remain unverified because Stage1 declines `bounded_title`/`bounded_view` and `app_event` codegen. `check_source_sizes.sh`, `git diff --check`, and strict `check_toolchain.sh` pass.

`feature_view_test`, `feature_presentation_test`, `feature_component_test`, and `feature_sdk_composition` compiled, linked, and passed on this tuple. The SDK/UI fixture now builds a
parent-owned retained screen from a bounded copied feature snapshot (UTF-8 title/body/action label plus an app action key); its retained view binds the key to the rendered content sequence, returns zero for stale or cleared visible content, and exposes the updated key only after refresh. `feature_sdk_composition` also verifies clear-watermark replay rejection and higher-sequence repopulation. The current-source
`check_wapp_features_ui.sh` also passed through the `wasmbrowser:features@1` runtime validator with `WASM_BROWSER_RUSTUP_TOOLCHAIN=stable` and an isolated
Cargo target; its guest publishes and reads the snapshot before acknowledged teardown.

The compiler's `struct_field_refinement_shadow_smoke.sh` passes its scoped-shadow controls on Stage0/Stage1. `driver_acceptance_smoke.sh` remains red only in
WITH-STD mode: BARE's five disagreements match ratchet 6; WITH-STD has four known acceptance gaps against ratchet 0 (`affine_container_return`,
`affine_spread_copy`, `darray_builtin_arity`, and `darray_mutable_receiver`).

## Current-source AppKit/UIKit resource upload adapters (2026-10-01)

`appkit_canvas_image_upload_test` and `scripts/check_uikit_image_upload.sh` passed: both adapters gate `Ready` on staged progress and bind host-owned CGImages. The fresh `services_test` also passes the typed `ServiceSelectionKind` contract: empty IDs, `Unknown`, and out-of-range kinds are rejected; `Image` identity round-trips.
`check_appkit_canvas_image_upload.sh` runs before the broad matrix and passed;
both adapters reject generation/native-object replacement before forget, allow
idempotent rebinding, and reject stale forgets. UIKit cross-compiles to an arm64
Simulator object; its fixtures cover binding lifecycle, not device pixels or
production callbacks. On 2026-10-01, `scripts/check_uikit.sh` passed on Stage1
revision `d8b5d305ec99` (product SHA-256 `c9120725bde202e70ea9ff94c9b87ab2026770eb5b29e95bfc1bc285f76eb9cf`; runtime SHA-256 `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb`) and Xcode 27.0: canvas and native-controls apps linked for simulator and device, shim/backend ABI checks passed, and the host-stub PNG digest was `6b3f05378ec45881bcadaa5c6ade3cab721b291414808117df20545ca9c3c9bf`. `scripts/build_uikit.sh uikit_services_smoke simulator canvas` also passed, compiling and linking the PhotosUI/Files picker smoke app; a second focused `uikit_services_test` run passed after the adapter cleanup. `check_uikit_simulator.sh` delivered 430pt@3×, safe-area, trait, Dynamic Type, and lifecycle changes, then both apps launched and painted; `check_uikit_touch.sh` passed a system-level tap and committed software-keyboard text (`Elisa`) through the retained model and semantic tree. The surface fixture also verifies slider values `0%`, `50%`, and `100%`; the simulator linker's `.tbd` message is non-fatal. An earlier simulator remained in CoreLocation first-boot migration for over five minutes; although this Xcode bundle has no Simulator.app, headless `scripts/check_uikit_services.sh` rebuilt the smoke app and passed XCUITest on a fresh iOS 26.5 simulator: PhotosUI and Files selections returned an image and a Documents text fixture, and both bounded reads and explicit releases completed. Other service-kind picker adapters remain open. A fresh `capabilities_test` run verifies `multiple_windows=false` for UIKit and Android canvas/native-controls profiles, and `mobile_surface_test` passes the single-surface lifecycle contract. The focused `services_test`, `uikit_services_test`, and `android_services_test` pass; UIKit/Android now bridge Camera/Microphone results into the shared consent records, with Android persisting the prior-prompt fact across process recreation. The Pixel_9 Android 37.1 AVD passes `check_android.sh showcase`; `check_android_ime.sh` passes CJK composition, visible/hidden insets, and unhandled Back after fixing its tap scaling to use full-display (not app-surface) coordinates. On 2026-10-01, `check_android.sh android_services_smoke` also passed on that AVD: the system Photo Picker returned a PNG, SAF returned a text fixture, and the app read and explicitly released bytes for both. This proves adapter linkage/state routing and platform smoke behavior, not a user-confirmed camera/microphone dialog or physical-device acceptance.
`check_wasmbrowser_transfer.sh` now checks all seven command tags, including
image fit, and confirms guest buffer-pointer reuse across two frames, through
native C host stubs: 224 command bytes; semantics remain 137 / 33,800 bytes and
the reusable buffer saves 92,152 static bytes. This is not typed SDK/real-host,
host-copy, or timing evidence. The hello resource demo now uses the shared presentation painter and retained image identity;
`showcase_workflow_test` and `resource_presentation_test` pass; workflow covers
180×48 placeholder/fallback, offline/denied refresh, retry/ready identity, and
800×680 plus 390×844 viewports. `UiResourceComponent` now owns the Hello demo's retained placeholder/status/progress/action controls, typed retry, generation rebind, fallback paint, accessible action semantics, and owner-scoped viewport demand; `resource_state_test`, `resource_presentation_test`, `resource_component_test`, and `showcase_workflow_test` pass, covering hint coalescing, visibility clear, retry/rebind transfer, terminal cleanup, host-operation download/decode/upload progress through retained refresh to exact Ready-image binding, offline/denied transitions, cancellation/reload, and desktop/phone geometry. The resource and showcase fixtures compile, link, and run against SDL3 with the default Xcode 27 linker after the attached Xcode-license/Homebrew repair, without `DEVELOPER_DIR` overrides; no SDK or system configuration changed. Skia retained replay/Painter code moved into `src/platform/skia/ui_skia_replay.elisa`; `skia_painter_test` passes; current CoreText-enabled `check_skia_offscreen.sh` and `check_showcase_skia.sh` pass, with exact archive hashes and scope in [text shaping and font sources](text-shaping-and-font-sources.md#focused-skia-evidence-2026-10-01). `check_skia.sh`/`check_appkit_skia.sh` are blocked when Stage1 declines `examples/showcase/appkit_skia_canvas_main.elisa` (`view@23019`); the Hello entry compiles, but the compositor host fixture is not reached. Independent `render_showcase_skia.sh` also declines `test/showcase_app_skia_test.elisa` (`view@17988`) before linking.
`text_lifecycle_workflow_test` also passes after adding a font-ready metrics-generation transition: retained text is remeasured while the focused field's value, selection, and active IME composition remain intact; a variable virtual list updates its height estimate, clears stale measured extents, remeasures the realized row, and retains the same logical scroll anchor and local offset. The SDL_ttf RTL direction change passes focused `sdl3_text_test`; current backend tuple and remaining limits are in [text shaping and font sources](text-shaping-and-font-sources.md#focused-sdl-evidence-2026-10-01) and [Apple Skia evidence](text-shaping-and-font-sources.md#focused-skia-evidence-2026-10-01). The Apple Skia path now also has a bounded shaped-blob LRU with explicit cache-hit, locale/scale/surface-loss invalidation, and capacity assertions; its end-to-end performance contribution remains unmeasured. `struct_field_refinement_shadow_smoke.sh` also passes on Stage1 product `4b36ce5a…e8e83fe`: valid block, assignment, loop, and match shadows compile, while the original unrefined by-value parameter is diagnosed again after its shadow scope closes. A fresh `driver_acceptance_smoke.sh` run rebuilt Stage0 from dirty Core HEAD `ff01f1b`; Stage1 was dirty at HEAD `3fa4a7e`. It failed both standing ratchets: bare mode has 8 disagreements (limit 6) and with-stdlib has 7 (limit 0), involving affine/container acceptance, borrow/view escapes, loop/parameter diagnostics, mutable receivers, and darray builtin arity. Older recorded counts use different dirty source tuples, so this change is unresolved and not attributed to the linker/toolchain repair or the field-refinement change.

## Historical evidence

Earlier compiler, Skia, mobile, Linux, Windows, hosted, and performance runs remain available in the repository's Git history and in `docs/implementation-baseline/renderer-verification-status.md`. Historical results are not reused as current evidence when the compiler product, source bundle, host, or native dependency tuple changes.
