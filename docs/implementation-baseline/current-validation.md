# Current validation

Part of the [elisa-ui implementation baseline](../implementation-baseline.md).

## Latest compiler and renderer evidence (2026-09-16)

The current framework revision is `03d6479` (with the preceding caret,
WasmBrowser, and renderer-budget commits `8342287`, `ff65837`, and `b68a10c`). Its variable-height list cache
uses deterministic least-recently-updated eviction at the fixed 256-entry
limit, typed handles expose a versioned snapshot/restore path, and the direct
Skia text ABI rejects malformed or oversized UTF-8 before measurement or draw;
the retained text-field caret keeps its public rectangle-origin contract while
painting the exact one-point rectangle; `test/virtual_list_variable_test.elisa`,
`test/widget_handles_test.elisa`, `test/widget_layout_text_test.elisa`,
`test/widget_caret_alignment_test.elisa`, and the real Skia off-screen host
cover these boundaries.

The fetched upstream `main` is
`45cb0ded70e7e8c8a41d21c63a09939706322ca4`. The shared compiler checkout is
clean on `main` at
`8617216995bc0801785928e2bc0cf8c73200df3d` (ahead=10, behind=0 versus the
fetched `origin/main`). Framework gates use this latest local build.

The latest clean stage1 used for the current gates is
`../Elisa-compiler/bin/elisac-stage1`, revision
`8617216995bc0801785928e2bc0cf8c73200df3d`. Its stage1 SHA-256 is
`eda6d29a7c9217c22b3b8210c134e776f5b0d3232fd902b8e4bd0927d7be2441` and its
runtime SHA-256 is
`85f1107eef00a7dd903e511df366b8b6cade4d8573cf0478f1de91604ea5beb9`.
The product and runtime were freshly self-hosted from the current stage0 and
the strict `ELISA_UI_REQUIRE_CURRENT_STAGE1=1` toolchain check passes.

The pinned Skia checkout is revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; `out/elisa/libskia.a` has SHA-256
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`.
The clean upstream-main, c605, ce9e, 4cf3, 0f08, 8d7, 45cb, d6a, and latest 8617
compiler products have separate exact performance tuples recorded in
`test/showcase_skia_performance_budgets.json`.

With the clean latest compiler and pinned Skia, the following headless gates
passed without opening or foregrounding a window:

```text
ELISA_UI_STAGE1=../Elisa-compiler \
bash scripts/check_appkit_canvas.sh
  -O2 AppKit canvas build, fresh-process PNG, accessibility bridge,
  callbacks, ordinary nested hierarchy, bundle and signature: PASS
  fresh-process PNG sha256=
  07f328d5e73e0f2863b08135085ff85046d6b5ffb451622d965d914b4c9011d1

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
with the clean latest 86172169 product after the exact-rectangle caret and
WasmBrowser lifecycle fixes. Three fresh processes produced 21 tail-pixel-stable
samples, with a recorded median of 10.498 ms and a maximum of 10.795 ms,
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
`d7aead96`, `56364e77`, and `86172169`; `scripts/check_wapp.sh` now reports a
JS-free component package with the expected imports/exports.

## Known optimized AppKit pixel issue

`test/appkit_canvas_surface_test.elisa` passes at `-O0` and `-O1` but fails five
lighting/ramp assertions at `-O2` with the clean latest compiler. The measured
pixels show the gradient primitives are receiving valid geometry; the failure
is isolated to generic retained replay's optimized aggregate argument ABI on
arm64 (mixed register/stack `SurfaceStyle`/`RoundedRectStyle` marshalling).
The direct painter path and a non-generic replay shape avoid the symptom, but
that workaround is not yet verified through the production callback. The
fixture therefore remains diagnostic and is intentionally not claimed as a
green required `-O2` gate. Do not mask this by lowering production optimization
to `-O1`; fix or validate the compiler/code-shape issue first.

The compiler-side differential is reproducible from the same stage-emitted IR:
re-emitting it with LLVM 23.1 `llc -O0` reproduces the five failures, while
`llc -O1` and `llc -O2` pass. The current compiler source hard-codes target
machine code generation at level `0` in `src/backend/codegen_target_machine.elisa`
(the `LLVMCreateTargetMachine` call), even when the stage driver has already
run an optimized IR pipeline. Propagating the requested level to that target
machine, or using a stable indirect aggregate ABI, is the narrow external fix.

## Historical evidence

Earlier compiler, Skia, mobile, Linux, Windows, hosted, and performance runs
remain available in the repository's Git history and in
`docs/implementation-baseline/renderer-verification-status.md`. Historical
results are not reused as current evidence when the compiler product, source
bundle, host, or native dependency tuple changes.
