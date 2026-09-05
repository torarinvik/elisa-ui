# Backend capability profiles

`UiCapabilities` is the portable fact surface for backend differences. The
selected adapter calls one profile constructor during startup; applications can
read the resulting `Snapshot` without checking an OS name or touching a native
object.

Profiles distinguish native windows, custom painting, native controls, hosted
presentation, text input and composition, clipboard, semantics, off-screen
rendering, scale changes, multiple windows, and deterministic test clocks. A
profile is deliberately conservative: an unsupported field is `false` until a
backend has an implementation and fixture for it.

The profile describes the selected backend's contract, while
`UiLifecycle::Snapshot` describes whether the current surface is actually live.
For example, `AppKitCanvas` advertises off-screen rendering because its Elisa
renderer has a bounded snapshot path; a failed window creation still leaves the
lifecycle in a non-rendering phase.

Current profiles:

- `Harness`: no native surface, deterministic clock, and inspectable semantics.
- `Sdl3`: native window and custom painting, with SDL text input and clipboard;
  semantic publication and scale-change handling are not claimed yet.
- `AppKit`: native controls and native semantics, without the custom canvas or
  canvas snapshot path.
- `AppKitCanvas`: custom painting, native text/IME, native semantics, and
  off-screen snapshots.
- `WasmBrowser`: hosted command presentation and host-mediated text/IME and
  clipboard; native-window and local-semantic capabilities are not claimed.

The read-only projection is also included in `UiInspector::Frame` so diagnostics
can record both the selected profile and the live lifecycle state.
