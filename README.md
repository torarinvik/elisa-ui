# elisa-ui

A cross-platform UI framework written in **Elisa**, targeting native desktop (SDL3)
and the WASM browser in lockstep. A RAD designer tool is planned on top. Eventually
expected to fold into the wasm-browser-sdk.

## Architecture (v0)

Two contracts keep every target buildable from the same app source:

- **Platform contract** (`src/core/ui_core.elisa` documents it): drawing primitives
  (`ui_clear`, `ui_fill_rect`, …) implemented by exactly one backend per binary —
  `src/platform/sdl3/` (native, system libSDL3 via externs) or `src/platform/web/`
  (WASM `env` imports provided by the host page).
- **App contract**: the application implements `app_init` / `app_event(UiEvent)` /
  `app_frame`. Native drives the loop from `ui_run`; on the web the page drives it
  through exported `ui_init` / `ui_frame` / `ui_pointer` entry points.

Backend selection is by include: each example has a `native_main.elisa` and a
`web_main.elisa` entry that include the same `app.elisa`.

wxWidgets serves as an architectural reference (widget hierarchy, sizers, event
routing) — studied, not ported.

## Build

Both scripts use the compiler worktrees in `../elisa-ui-worktrees/` (override with
`ELISA_UI_STAGE1`):

```sh
scripts/build_native.sh   # -> build/hello_native (needs brew's sdl3)
scripts/build_wasm.sh     # -> build/hello_web.wasm + generated .mjs loader
```

Run native: `./build/hello_native` (headless check: `SDL_VIDEODRIVER=dummy
ELISA_UI_SMOKE_FRAMES=1 ./build/hello_native`). Run web: serve the repo root
(`python3 -m http.server`) and open `examples/hello/index.html`.
