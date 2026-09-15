# elisa-ui implementation baseline

Recorded 2026-09-08 on macOS arm64; refreshed 2026-09-15 on main.
This is the durable UI-00 audit for the
local implementation plan; it records observed behavior, not an assumption of
parity on untested platforms.

## Reproducibility tuple

### Active toolchain snapshot (2026-09-15)

| Item | Observed value |
| --- | --- |
| elisa-ui code revision | b61b97a on main (committed task state; working tree clean) |
| Host and C compiler | macOS 26.6.2 (Darwin 25.6.0), arm64; Homebrew clang 23.1.1 |
| Elisa stage1 | latest local build `../Elisa-compiler/bin/elisac-stage1`, revision 565ccb2fd585d03f94457185376f526e1930b1cb (main, ahead of fetched origin/main); SHA-256 2324bf11c796433ac2868b4dc5d4c8ab26f4e471e30dfafb3d3067a1f159dd17 |
| Elisa runtime | `../Elisa-compiler/build/runtime/elisacore_runtime.o`; SHA-256 85f1107eef00a7dd903e511df366b8b6cade4d8573cf0478f1de91604ea5beb9 |
| Elisa stage1 driver | `scripts/elisac_stage1.sh` from the latest local compiler; SHA-256 9b23b66c0b8edbf292d14b444f506c2e30be237943126ffe455d1c8e2873756f |
| Upstream-main compiler reference | fetched `origin/main` at 45cb0ded70e7e8c8a41d21c63a09939706322ca4; the local main build above is five commits ahead and zero behind |
| Shared compiler checkout | `../Elisa-compiler` is on clean branch `main` at 565ccb2fd585d03f94457185376f526e1930b1cb (ahead=5, behind=0 versus fetched `origin/main`); current gates use this latest local build. |
| Clang binary | `/opt/homebrew/opt/llvm/bin/clang++`, Homebrew clang 23.1.1; SHA-256 570c488e53383b198796e706e91b5ce5ec45bb730683a5af5e822d56a2eb1888 |
| Skia source/archive | chrome/m150 at 9c7b2dffb2433f5a0cc2b77f06025a09126807ed; `out/elisa/libskia.a` SHA-256 39774ff993bd3b84943c27548738c8b8b8208396237d536c1a4ed1c6e147c775; optional `libpng.a` SHA-256 13fda447a526c821e1bff29f66b3a582857d702e9f8fd8e5f29b5628dfe2690f |
| WasmBrowser | ../WasmBrowser at 3ac9b25b0ea74000846625f46c2115ac93d16cf1; checkout has pre-existing local changes; WIT SHA-256 unchanged at 9032a1c59a5495d4868bc7cdf494153096708ff6f2321b4ea2ffeff752c627d6 |
| wasm-sdk | ../wasm-sdk at fa832f0e812254b0edb0447a17078397911c3d01; checkout has pre-existing local changes |
| Rust/Wasm linker | rustc 1.98.1 (Homebrew); wasm-component-ld is not on PATH |
| Native libraries | Homebrew SDL3 3.4.16 and SDL_ttf 3.2.2 under /opt/homebrew/lib |

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
- [Workstream status and evidence](implementation-baseline/plan-status.md)
- [Decision records](implementation-baseline/decision-records.md)
