# elisa-ui implementation baseline

Recorded 2026-09-08 on macOS arm64; refreshed 2026-09-12 on main.
This is the durable UI-00 audit for the
local implementation plan; it records observed behavior, not an assumption of
parity on untested platforms.

## Reproducibility tuple

| Item | Observed value (2026-09-08) | Observed value (2026-09-12, main) |
| --- | --- | --- |
| elisa-ui revision | `57a4022` (`test: cover direct malformed pointer normalization`) on branch `work` | `a17b5c1` (`win32: link a real image, and stop claiming one is out of reach`) on branch `main` |
| Host | Darwin 25.6.0, arm64 (`Torarins-MacBook-Air.local`) | Darwin 25.6.0, arm64 (`Torarins-MacBook-Air.local`) |
| C compiler | Homebrew clang 23.1.0 | Homebrew clang 23.1.1 |
| Elisa compiler | `../wasm-sdk-compiler/bin/elisac-stage1` on clean `codex/wasm-sdk`, revision `c6948142f19d`; SHA-256 `56945beffa13240afdd004ac7590580b56f11c7406fc82c16309f6bd9025e574` | `../wasm-sdk-compiler/bin/elisac-stage1` on clean `codex/wasm-sdk`, revision `986a30b9d6a1`; SHA-256 `57bdf193b26209e3dd581d97a49401d98d69ad9815bac732b099804fe818a4ee` |
| Skia source pin | `chrome/m150` at `9c7b2dffb2433f5a0cc2b77f06025a09126807ed`; build contract in `third_party/skia.lock` | unchanged: `chrome/m150` at `9c7b2dffb2433f5a0cc2b77f06025a09126807ed` |
| Elisa runtime | `../wasm-sdk-compiler/build/runtime/elisacore_runtime.o`; SHA-256 `cb06532f0c37540284de4ceaa622d0da9193f113877ac391fb00bad4bf9ff1e9` | `../wasm-sdk-compiler/build/runtime/elisacore_runtime.o`; SHA-256 `98aee21d1a0b535b62693d706c4884cf7ea0273dbe49488f2b84dba5c79268cb` |
| WasmBrowser checkout | revision `b40bb17a3141` (host worktree has unrelated local runtime edits) | revision `2f8bc5be1160` (worktree has local `wb_protocol`/CLI/commerce/loader edits) |
| WasmBrowser WIT | `../WasmBrowser/wit/wasmbrowser.wit`; SHA-256 `9032a1c59a5495d4868bc7cdf494153096708ff6f2321b4ea2ffeff752c627d6` | unchanged SHA-256 `9032a1c59a5495d4868bc7cdf494153096708ff6f2321b4ea2ffeff752c627d6` |
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
