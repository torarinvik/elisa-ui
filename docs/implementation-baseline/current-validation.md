# Current validation

Part of the [elisa-ui implementation baseline](../implementation-baseline.md).

## Latest compiler and renderer evidence (2026-09-15)

The fetched upstream `main` is
`fd2cb3cff470319500db362e5fce283cbe300de`. The shared compiler checkout is on
`codex/shared-typed-edir-lowering` at `c605b3faa516de7b2f4945a9ac4ccb21d78ae2e0`
with uncommitted work; it was left untouched. Framework gates use a clean
isolated compiler checkout instead.

The latest clean stage1 used for the current gates is at
`/private/tmp/elisa-compiler-ui-latest`, revision
`0f08a3ca78986fae9297fa412809c1aea3adc80f`, thirteen commits ahead of fetched
upstream `main`. Its stage1 SHA-256 is
`478a3e45ee0c5d7ac066e883990514c16c034f2fb33383bf29be8ab7ca8b2029` and its
runtime SHA-256 is
`a58618f5358e30e8c19cf1344d47bddd3a7520ee61f83a471222bb0660e48a8f`.
`ELISA_UI_STAGE1=/private/tmp/elisa-compiler-ui-latest bash
scripts/check_toolchain.sh` passes the strict dirty/stale checks.

The pinned Skia checkout is revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; `out/elisa/libskia.a` has SHA-256
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`.
The clean upstream-main, c605, ce9e, 4cf3, and latest 0f08 compiler products
have separate exact performance tuples recorded in
`test/showcase_skia_performance_budgets.json`.

With the clean latest compiler and pinned Skia, the following headless gates
passed without opening or foregrounding a window:

```text
ELISA_UI_STAGE1=/private/tmp/elisa-compiler-ui-latest \
bash scripts/check_appkit_canvas.sh
  -O2 AppKit canvas build, fresh-process PNG, accessibility bridge,
  callbacks, bundle and signature: PASS
  fresh-process PNG sha256=
  07f328d5e73e0f2863b08135085ff85046d6b5ffb451622d965d914b4c9011d1

ELISA_UI_STAGE1=/private/tmp/elisa-compiler-ui-latest \
bash scripts/check_capi.sh
  C header/Elisa symbol agreement and C example: PASS

ELISA_UI_STAGE1=/private/tmp/elisa-compiler-ui-latest \
bash scripts/check_uikit.sh
  UIKit SDK syntax, ABI, off-screen frame and semantic boundary: PASS

`test/uikit_virtual_accessibility_test.elisa` (compiled and linked with the
same latest stage1/runtime and `test/uikit_host_stubs.c`): headless UIKit
virtual-container provider, million-row reveal, bounded proxy identities,
activation and teardown: PASS

ELISA_UI_STAGE1=/private/tmp/elisa-compiler-ui-latest \
SKIA_ROOT=/tmp/elisa-skia-check-20260914 \
bash scripts/check_skia.sh
  CPU-raster painter, off-screen pixels, fresh-process replay, Showcase pages,
  deferred resource replacement and state variants: PASS
```

`check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh`, and
`check_unicode_conformance.sh` also pass with this compiler. The Unicode gate
executes the pinned UAX #29 15.1.0 corpus (1,187 rows).

The full real-Skia Showcase path reached its required exact-tuple benchmark
with the clean latest 0f08a3ca product. Three fresh processes produced 21 tail
pixel-stable samples, with a median of 29.330 ms and a maximum of 39.061 ms,
inside the recorded 40/55 ms policy limits. The tuple is recorded in
`test/showcase_skia_performance_budgets.json`; a different compiler or host
must add its own measured reference instead of inheriting this result.

The hosted open-vertical-slice gate reaches component-runtime compilation but
still fails on compiler-generated invalid LLVM IR:

```text
declare i32 @llvm.wasm.memory.grow.i32.i32(i32, i32)
```

The expected intrinsic is `llvm.wasm.memory.grow.i32`. This is a compiler
backend blocker, not evidence of a framework or WasmBrowser API failure.

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
