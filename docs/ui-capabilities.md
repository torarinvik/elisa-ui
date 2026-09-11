# Backend capability profiles

`UiCapabilities` is the portable fact surface for backend differences. The
selected adapter calls one profile constructor during startup; applications can
read the resulting `Snapshot` without checking an OS name or touching a native
object. The snapshot also identifies the renderer that owns custom pixels:
native controls, SDL3, CoreGraphics fallback, Skia, hosted commands, or the
headless test renderer. Scale-change support is reported independently and is
enabled when the selected custom renderer can accept a new logical-to-physical
scale without rebuilding retained widget state.

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

- `Harness`: no native surface, deterministic clock, and inspectable semantics;
  renderer `Headless`.
- `Sdl3`: native window and custom painting, with SDL text input and clipboard;
  semantic publication and scale-change handling are not claimed yet; renderer
  `Sdl3`.
- `AppKit`: native controls and native semantics, without the custom canvas or
  canvas snapshot path; renderer `Native`.
- `AppKitCanvas`: custom painting, native text/IME, native semantics, and
  off-screen snapshots; the current fallback reports `CoreGraphics`, while a
  live `UiSkia` canvas selects renderer `Skia` and enables scale changes.
- `UiKit`: the same retained batch painted through CoreGraphics on iOS. It
  differs from the Mac canvas in what an application may rely on: the surface
  changes scale and orientation under it, and there is no second window.
- `UiKitControls`: real UIKit controls. UIKit owns every pixel, the IME,
  mirroring, Dynamic Type and VoiceOver, so no custom paint and no off-screen
  frame are claimed; renderer `Native`.
- `Android`: the Skia-painted canvas on Android — custom painting, native
  text/IME through a real `InputConnection`, and the system clipboard. It
  claims **no** semantics (TalkBack is served by `AndroidControls`, not by the
  painted canvas) and **no** off-screen snapshot, and it does change scale,
  because the device rotates. Renderer `Skia`.
- `AndroidControls`: real `android.widget` views; the toolkit draws, runs its
  own IME and speaks to TalkBack. Renderer `Native`.
- `Gtk`: real GTK controls, which is how Linux gets a native backend at all.
  The toolkit draws, runs its own IME and speaks to Orca; multiple windows are
  a `GtkWindow` away. Renderer `Native`.
- `Win32`: real Windows controls — the toolkit draws, runs its own IME and
  speaks to Narrator, with real multiple windows. Renderer `Native`.
- `WasmBrowser`: hosted command presentation and host-mediated text/IME and
  clipboard; native-window and local-semantic capabilities are not claimed;
  renderer `Hosted`.

A profile is a set of claims an application is entitled to act on, so a backend
borrowing the nearest existing one is a bug rather than a shortcut. The painted
Android backend answered `use_appkit_canvas()` until it had a profile of its
own, which told every caller it was running on macOS with semantics and
snapshots it has never had.

The read-only projection is also included in `UiInspector::Frame` so diagnostics
can record both the selected profile and the live lifecycle state.
