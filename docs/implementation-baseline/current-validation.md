# Current validation

Part of the [elisa-ui implementation baseline](../implementation-baseline.md).

## Latest compiler and renderer evidence (2026-09-15)

The fetched upstream `main` is
`fd2cb3cff470319500db362e5fce283cbe300de`. The shared compiler checkout is on
`codex/shared-typed-edir-lowering` at `c605b3faa516de7b2f4945a9ac4ccb21d78ae2e0`
with uncommitted work; it was left untouched. Framework gates use a clean
isolated compiler checkout instead.

The latest clean isolated stage1 used for the AppKit check is at
`/tmp/elisa-ui-compiler-c605-20260915`, revision
`ce9e0292f40a6618b7803a4b9b07961d08033a5e`, three commits ahead of fetched
upstream `main`. Its stage1 SHA-256 is
`9c8e31c9902ba6d0106c9e2eb2cbcdb68992efd3faa264ed8c220e2ab5387682` and its
runtime SHA-256 is
`a58618f5358e30e8c19cf1344d47bddd3a7520ee61f83a471222bb0660e48a8f`.
`ELISA_UI_STAGE1=/tmp/elisa-ui-compiler-c605-20260915 bash
scripts/check_toolchain.sh` passes the strict dirty/stale checks.

The pinned Skia checkout is revision
`9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; `out/elisa/libskia.a` has SHA-256
`39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775`.
The clean upstream-main and c605 compiler products have separate exact
performance tuples recorded in `test/showcase_skia_performance_budgets.json`.

With the clean latest compiler and pinned Skia, the following headless gates
passed without opening or foregrounding a window:

```text
ELISA_UI_STAGE1=/tmp/elisa-ui-compiler-c605-20260915 \
bash scripts/check_appkit_canvas.sh
  -O2 AppKit canvas build, fresh-process PNG, accessibility bridge,
  callbacks, bundle and signature: PASS
  fresh-process PNG sha256=
  07f328d5e73e0f2863b08135085ff85046d6b5ffb451622d965d914b4c9011d1

ELISA_UI_STAGE1=/tmp/elisa-ui-compiler-c605-20260915 \
bash scripts/check_capi.sh
  C header/Elisa symbol agreement and C example: PASS

ELISA_UI_STAGE1=/tmp/elisa-ui-compiler-c605-20260915 \
bash scripts/check_uikit.sh
  UIKit SDK syntax, ABI, off-screen frame and semantic boundary: PASS

ELISA_UI_STAGE1=/tmp/elisa-ui-compiler-c605-20260915 \
SKIA_ROOT=/tmp/elisa-skia-check-20260914 \
bash scripts/check_skia.sh
  CPU-raster painter, off-screen pixels, fresh-process replay, Showcase pages,
  deferred resource replacement and state variants: PASS
```

`check_source_sizes.sh`, `check_global_names.sh`, `check_refinements.sh`, and
`check_unicode_conformance.sh` also pass with this compiler. The Unicode gate
executes the pinned UAX #29 15.1.0 corpus (1,187 rows).

The full `run_tests.sh` invocation reached all early headless checks and the
public million-item Showcase workflow, but its required exact-tuple benchmark
correctly stopped because the ce9e product was not yet represented in the
recorded budget. One run also had a transient 48.6 ms sample, above the 40 ms
maximum. Existing c605 and upstream-main tuples remain the accepted performance
references; an unbudgeted product is not silently accepted.

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

## Historical evidence

Earlier compiler, Skia, mobile, Linux, Windows, hosted, and performance runs
remain available in the repository's Git history and in
`docs/implementation-baseline/renderer-verification-status.md`. Historical
results are not reused as current evidence when the compiler product, source
bundle, host, or native dependency tuple changes.
