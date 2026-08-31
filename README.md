# elisa-ui

A cross-platform UI framework written in **Elisa**, targeting native desktop
(SDL3) and [WasmBrowser](../WasmBrowser) in lockstep. A RAD designer tool is
planned on top. Eventually expected to fold into the wasm-browser-sdk.

**The web target is WasmBrowser, not an ordinary browser.** WasmBrowser is a
Wasmtime component host that loads `.wapp` packages whose only payload is
`manifest.json` plus a Wasm component. Nothing here emits JavaScript, an ESM
loader, or TypeScript declarations, and nothing should.

## Architecture

Drawing is **retained**. An app's frame appends to a command batch; the backend
consumes the whole batch at frame end. That is what
`wasmbrowser:window/host@0.1.0`'s `present-commands` takes (one list per frame),
and it is also what the manifest's `hybrid` execution mode requires — remote app
logic with local presentation. SDL3 loses nothing by replaying the batch.

- **Core** ([src/core/ui_core.elisa](src/core/ui_core.elisa)) — colour/geometry
  records mirroring the WIT records field-for-field, the `UiCommand` batch, the
  drawing API that appends to it, and `UiEvent`. Knows nothing about any wire
  format.
- **Backends** implement the platform side and own the frame loop:
  [sdl3](src/platform/sdl3/ui_sdl3.elisa) (native; externs against system
  libSDL3; `ui_run` drives the loop) and
  [wasmbrowser](src/platform/wasmbrowser/ui_wasmbrowser.elisa) (a component
  implementing `world app`; the host drives the loop through the exported guest
  interface, and canonical-ABI encoding is confined to this file).
- **Apps** implement `app_init` / `app_event(UiEvent)` / `app_frame`.

Backend selection is by include: each example has a `native_main.elisa` and a
`wapp_main.elisa` entry that include the same `app.elisa`.

wxWidgets serves as an architectural reference (widget hierarchy, sizers, event
routing) — studied, not ported.

## Build

Both scripts use the compiler worktrees in `../elisa-ui-worktrees/` (override
with `ELISA_UI_STAGE1`):

```sh
scripts/build_native.sh   # -> build/hello_native (needs brew's sdl3)
scripts/build_wapp.sh     # -> build/hello.wapp (+ build/hello.wasm)
```

The `.wapp` build needs `wasm-component-ld` (ships with Rust's `wasm32-wasip2`
target) and the `wasm-browser` CLI for the packing step; set `WASM_BROWSER_CLI`
or run `cargo build -p wb-cli` in the WasmBrowser checkout. It finds the WIT
world at `../WasmBrowser/wit/wasmbrowser.wit` (override with `ELISA_UI_WIT`).

Run native: `./build/hello_native`; headless check with
`SDL_VIDEODRIVER=dummy ELISA_UI_SMOKE_FRAMES=1 ./build/hello_native`. Inspect the
package with `wasm-browser inspect build/hello.wapp`.

### Elisascript ports (not yet runnable)

`build_native.elisascript` and `build_wapp.elisascript` are ports of the two
shell scripts to [Elisascript](../elisa-script), intended to replace them. They
are **unvalidated**: the Elisascript toolchain does not currently build against
the present Elisa compiler, so nothing has lowered or run them yet. The `.sh`
scripts remain the working path until then.
