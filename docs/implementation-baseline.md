# elisa-ui implementation baseline

Recorded 2026-09-08 on macOS arm64; refreshed 2026-09-30 from the live
checkouts on main.
This is the durable UI-00 audit for the
local implementation plan; it records observed behavior, not an assumption of
parity on untested platforms.

## Reproducibility tuple

### Active toolchain snapshot (2026-09-30)

| Item | Observed value |
| --- | --- |
| elisa-ui Git state | `9487a79` (`remote: expose bounded semantic nodes`) on `main`, 0 ahead/behind `origin/main`; working tree dirty (223 status entries at sampling, before this refresh). |
| Host and Apple toolchain | macOS 27.0 (Darwin 27.0.0), arm64; Xcode 27.0 build `27A266a`, selected developer directory `/Applications/Xcode.app/Contents/Developer`. License acceptance and Homebrew upgrade are complete; default and explicit-Xcode C/C++ link checks pass. |
| Stage1 selection | `bash scripts/resolve_stage1_root.sh .` selects `../Elisa-compiler`; product revision `3fa4a7e590c3ae5919b759a85dc8f1e105246c8b` on `main`, two commits ahead and zero behind `origin/main` (`ce52ba2c5261ebced8f5dae9ca1e21f25db8f460`); compiler checkout is dirty (49 status entries). Product SHA-256 `4b36ce5a7dcf4c448ee037dce4ec393b603ed90d15aa534a90ee3888be8e83fe`. |
| Elisa runtime | `../Elisa-compiler/build/runtime/elisacore_runtime.o`; SHA-256 `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb` |
| Elisa stage1 driver | `../Elisa-compiler/scripts/elisac_stage1.sh`; SHA-256 `f242c03380cb4e1e75f1116bef57a48961319d81bbd2cf7de47c9865cfcbfb7e` |
| Installed compiler snapshot | Installer snapshot `b841e64b`, captured 2026-09-27; separately passes the strict freshness check and builds/runs the C API example. The shell resolver prefers explicit selection, then adjacent development checkout, then this installed snapshot; see [current validation](implementation-baseline/current-validation.md). |
| C compiler | `/opt/homebrew/opt/llvm/bin/clang++`, Homebrew clang 23.1.1; SHA-256 `b0a040ee4ff1ed0da511d816be6539a8ee1827c2574135cfd31ad2e6354caa21` |
| WasmBrowser host/WIT | `../WasmBrowser` at `f2964aea83b0377c55220efa4aaa4ea55a0dee5f` on `main`, ten commits ahead of `origin/main`, with three local status entries. `wasmbrowser:window@0.1.0`; WIT SHA-256 `fca6734b226558ccaf2ff590bcf05819c654b738da8d701aabd39bd143665d1a`. |
| wasm-sdk | `../wasm-sdk` at `fa832f0e812254b0edb0447a17078397911c3d01` on `main`, 0 ahead/behind `origin/main`, with 98 local status entries; the selected input package declares `wasmbrowser:input@0.1.0`. |
| Rust/Wasm linker | rustc 1.98.1 (Homebrew); `wasm-component-ld` is not on `PATH` |
| Native libraries | Homebrew LLVM 23.1.1_1, SDL3 3.4.16, SDL_ttf 3.2.2, and pkgconf 3.0.7 under `/opt/homebrew`; SDL link checks pass. |
| Skia | `third_party/skia.lock` pins `chrome/m150` at `9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; renderer verification last records a 2026-09-17 tuple, which plan status marks stale for the current host/source. Do not treat it as current renderer acceptance. |

Example behavior on this tuple is recorded separately from package presence:
the C and Go linked examples, Wapp profile/runtime gates, Hello resource and
validation workflows, and Showcase retained-tree workflow have passing focused
evidence. The 2026-09-30 broad suite remains partial, with backend codegen
declines and skipped platform legs; see [current validation](implementation-baseline/current-validation.md)
and the [backend matrix](implementation-baseline/backend-and-feature-matrix.md).

The renderer status and exact verification outcomes are in
[current validation](implementation-baseline/current-validation.md) and
[renderer verification](implementation-baseline/renderer-verification-status.md).

| Item | Observed value (2026-09-08) | Observed value (2026-09-12, main) |
| --- | --- | --- |
| elisa-ui revision | `57a4022` (`test: cover direct malformed pointer normalization`) on branch `work` | `a17b5c1` (`win32: link a real image, and stop claiming one is out of reach`) on branch `main` |
| Host | Darwin 25.6.0, arm64 (`Torarins-MacBook-Air.local`) | Darwin 25.6.0, arm64 (`Torarins-MacBook-Air.local`) |
| C compiler | Homebrew clang 23.1.0 | Homebrew clang 23.1.1 |
| Elisa compiler | `../wasm-sdk-compiler/bin/elisac-stage1` on clean `codex/wasm-sdk`, revision `c6948142f19d`; SHA-256 `56945beffa13240afdd004ac7590580b56f11c7406fc82c16309f6bd9025e574` | `../wasm-sdk-compiler/bin/elisac-stage1` on clean `codex/wasm-sdk`, revision `986a30b9d6a1`; SHA-256 `57bdf193b26209e3dd581d97a49401d98d69ad9815bac732b099804fe818a4ee` |
| Skia source pin | `chrome/m150` at `9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; build contract in `third_party/skia.lock` | unchanged: `chrome/m150` at `9c7b2dffb2433f5a0cc2b77f06025a09126807ed` |
| Elisa runtime | `../wasm-sdk-compiler/build/runtime/elisacore_runtime.o`; SHA-256 `cb06532f0c37540284de4ceaa622d0da9193f113877ac391fb00bad4bf9ff1e9` | `../wasm-sdk-compiler/build/runtime/elisacore_runtime.o`; SHA-256 `98aee21d1a0b535b62693d706c4884cf7ea0273dbe49488f2b84dba5c79268cb` |
| WasmBrowser checkout | revision `b40bb17a3141` (host worktree has unrelated local runtime edits) | revision `2f8bc5be1160` (worktree has local `wb_protocol`/CLI/commerce/loader edits) |
| WasmBrowser WIT | `../WasmBrowser/wit/wasmbrowser.wit`; SHA-256 `3e9f8c202a4feca3b10edfda8d82a831e06f5da63b0b829de4666e6dc55cfb32` | aligned with the SDK contract and runtime binding |
| wasm-sdk checkout | revision `15024adfe066` (standalone SDK contract provenance and package validation) | revision `fa832f0e8122` |
| Rust component linker | rustc 1.98.0; `wasm-component-ld` from the stable aarch64 toolchain | rustc 1.98.1 (Homebrew); `wasm-component-ld` not on PATH |
| Native libraries | Homebrew SDL3 3.4.14 and SDL_ttf 3.2.2 under `/opt/homebrew/lib` | Homebrew SDL3 3.4.16 and SDL_ttf 3.2.2 under `/opt/homebrew/lib` |

The hello manifest now declares the versioned `wasmbrowser:component@1`
profile, Elisa language, and elisa-ui framework explicitly.

The hello reference app resolves its dark/light palette through `UiTheme` and
applies framework-wide tokens with `UiHandles::apply_palette`; its custom
accent remains application-owned while the adapter preserves retained widget
colors and geometry.

## Sections

The baseline is recorded in one chapter per audit area:

- [Renderer verification status](implementation-baseline/renderer-verification-status.md)
- [Source and boundary inventory](implementation-baseline/source-and-boundary-inventory.md)
- [Backend and feature matrix](implementation-baseline/backend-and-feature-matrix.md)
- [Current validation](implementation-baseline/current-validation.md)
- [Ownership decisions and next gaps](implementation-baseline/ownership-decisions-and-next-gaps.md)
- [Workstream status and evidence](implementation-baseline/plan-status.md)
- [Decision records](implementation-baseline/decision-records.md)
