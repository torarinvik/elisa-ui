# Current validation

Part of the [elisa-ui implementation baseline](../implementation-baseline.md).

## Latest local follow-up (2026-09-17)

The shared `Elisa-compiler` checkout advanced with intentional local compiler
fixes after the clean `5329edfd` baseline below. A fresh stage1 self-host from
that source produced product SHA-256
`5c77c7d86f26f19a43edb21502bbf3146d901c6453e172f5d0d99df423a4aba4` with the
same runtime and Skia pin. The required headless Skia painter, Showcase
workflow, exact-tuple renderer budget, generic performance budget, and focused
AppKit-Skia gate all passed; the current Showcase run retained the stable tail
digest `1ac21e37972207bb` and measured 14.512 ms median/17.024 ms maximum,
within the 50/80 ms policy limits. The deferred-text cleanup now scrubs the
complete fixed arena, independent of queue metadata. The generic retained
benchmark remains covered by the exact current tuple. Because the
sibling compiler working tree is intentionally dirty, these local checks use
`ELISA_ALLOW_DIRTY_STAGE1=1`; the exact host/compiler/Skia/source tuples are
recorded in both performance manifests rather than silently inheriting the
clean baseline.

## Latest compiler and renderer evidence (2026-09-17)

The 2026-09-17 follow-up fixes Elisa-owned RTL horizontal scrollbar paging: the
painted thumb, hit-test geometry, and page delta now share the same direction
transform. `test/widget_layout_scroll_test.elisa` covers a physical track click
away from the mirrored thumb as well as drag behavior. The fix is committed as
`0bba021`; its required real-Skia source bundle is
`85c9f05ff5532e0bd43273aec8e2f0dfce6f21d3db6301ddf2251cd7a586957f`.
The gates were rebuilt with the latest local compiler product at revision
`bfedb0d707a00797ddd16341f21a8b6e0a9677af` (product SHA
`a73be5e165b9a53b4b69495d006f24b719a9749182d6e57b5e92958e8ce28f36`, runtime
SHA `dbed0552a85df51da0c050e4f009bb7c565f792a0676df0f465e9e986e8845a4`).
The sibling checkout contains intentional local compiler edits, so this
follow-up used `ELISA_ALLOW_DIRTY_STAGE1=1`; the exact tuples are recorded in
the performance manifests and passed the required gates. The current retained
benchmark measured a 1.824 ms median batch (3.898 ms maximum), while the
current real-Skia Showcase workflow measured an 11.512 ms median (12.186 ms
maximum); both retained stable tail digest `1ac21e37972207bb`.

The preceding framework source revision was `d880c20` (with the preceding caret,
WasmBrowser, renderer-budget, and validation-document commits `8342287`,
`ff65837`, `b68a10c`, `b5ec623`, and `5d6c3e8`). Its variable-height list cache
uses deterministic least-recently-updated eviction at the fixed 256-entry
limit, typed handles expose a versioned snapshot/restore path, and the direct
Skia text ABI rejects malformed or oversized UTF-8 before measurement or draw;
the retained text-field caret keeps its public rectangle-origin contract while
painting the exact one-point rectangle; sealed hierarchy roots now support
Elisa-owned overlay grouping with a shared scrim and modal hit floor;
`test/virtual_list_variable_test.elisa`,
`test/widget_handles_test.elisa`, `test/widget_layout_text_test.elisa`,
`test/widget_caret_alignment_test.elisa`, and the real Skia off-screen host
`test/hierarchy_overlay_test.elisa` cover these boundaries.

The fetched upstream `main` is
`45cb0ded70e7e8c8a41d21c63a09939706322ca4`. The shared compiler checkout is
clean on `main` at
`5329edfdbefa27b5c1c51253da0073256ed51058` (ahead=11, behind=0 versus the
fetched `origin/main`). Framework gates use this latest local build.

The latest clean stage1 used for the current gates is
`../Elisa-compiler/bin/elisac-stage1`, revision
`5329edfdbefa27b5c1c51253da0073256ed51058`. Its stage1 SHA-256 is
`03fb7200424b6849ea3243c33e774270b4e8909a080136d05092251254b52024` and its
runtime SHA-256 is
`85f1107eef00a7dd903e511df366b8b6cade4d8573cf0478f1de91604ea5beb9`.
The product and runtime were freshly self-hosted from the current stage0 and
the strict `ELISA_UI_REQUIRE_CURRENT_STAGE1=1` toolchain check passes.

The pinned Skia checkout is revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; `out/elisa/libskia.a` has SHA-256
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`.
The clean upstream-main, c605, ce9e, 4cf3, 0f08, 8d7, 45cb, d6a, 8617, and
latest 5329 compiler products have separate exact performance tuples recorded in
`test/showcase_skia_performance_budgets.json`.

With the clean latest compiler and pinned Skia, the following headless gates
passed without opening or foregrounding a window:

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

`check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh`, and
`check_unicode_conformance.sh` also pass with this compiler. The Unicode gate
executes the pinned UAX #29 15.1.0 corpus (1,187 rows).

The full real-Skia Showcase path reached its required exact-tuple benchmark
with the clean latest 5329edfd product after the target-machine optimization
level, exact-rectangle caret, WasmBrowser lifecycle, and sealed-hierarchy
overlay changes. Three fresh processes produced 21 tail-pixel-stable samples,
with a recorded median of 20.013 ms and a maximum of 23.934 ms,
inside the current 50/80 ms policy limits. The exact source-bundle tuple is
recorded in
`test/showcase_skia_performance_budgets.json`; a different compiler, source
bundle, or host must add its own measured reference instead of inheriting this
result.

The complete `SKIA_ROOT=/private/tmp/elisa-skia-check-20260914
bash scripts/run_tests.sh` matrix now passes every local compiler, renderer,
native, mobile-simulator, cross-target, Unicode, portable, and hosted Wapp
fixture. The custom Android canvas leg is skipped because this host
has no built Android Skia archive or attached Android device. The Android
native-controls package half is independently green through
`scripts/check_android_controls.sh showcase`.

Variable-height retained lists also accept a synchronous application
measurement provider. The provider can supply logical row extents before
intrinsic fallback. Typed handles expose a bounded, versioned measurement
snapshot/restore path owned by Elisa, with full validation before cache
replacement; `test/widget_handles_test.elisa` covers provider replacement,
cache invalidation, intrinsic fallback, enumeration, and persistence.

## Hosted open vertical-slice gate (2026-09-16)

The hosted open-vertical-slice gate now builds and inspects the component
package successfully. The compiler-side fix corrected WebAssembly intrinsic
overload selection (`llvm.wasm.memory.grow.i32`/`size.i32`), and the
freestanding component runtime now provides the compiler-emitted
`ctx_string_views_eq` helper. Resize and pointer lifecycle callbacks use the
typed `UiCore::EventRecord` path so no unresolved `env::UiWasmBrowser.*`
imports are emitted.

The previous failure was:

```text
declare i32 @llvm.wasm.memory.grow.i32.i32(i32, i32)
```

The expected intrinsic is `llvm.wasm.memory.grow.i32`. The repaired compiler
and runtime are committed in the sibling `Elisa-compiler` checkout at
`d7aead96`, `56364e77`, `86172169`, and `5329edfd`; `scripts/check_wapp.sh` now reports a
JS-free component package with the expected imports/exports.

## Optimized AppKit validation

`test/appkit_canvas_surface_test.elisa` now passes at `-O2` with the clean
latest compiler. The compiler target-machine setup uses the same optimization
level as the IR pipeline instead of always lowering through LLVM at level 0;
the change is committed in sibling `Elisa-compiler` revision `5329edfd`.
This removes the mixed O2/O0 lowering path that previously exposed arm64
aggregate ABI differences in retained replay. The AppKit Canvas and AppKit/Skia
production callbacks both pass their off-screen optimized checks.

## Historical evidence

Earlier compiler, Skia, mobile, Linux, Windows, hosted, and performance runs
remain available in the repository's Git history and in
`docs/implementation-baseline/renderer-verification-status.md`. Historical
results are not reused as current evidence when the compiler product, source
bundle, host, or native dependency tuple changes.
