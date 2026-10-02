# Mobile surface facts

`UiMobileSurface` is the shared Elisa contract for Android and iOS adapters.
Adapters report logical viewport size, scale, safe-area edges, keyboard
occlusion, and surface recreation through this module while `UiLifecycle` owns
focus, background, and rendering eligibility. `snapshot()` derives the current
content area and orientation through `UiResponsive`.

This state represents one current primary surface for the application process;
it is not a multiwindow manager. The selected `UiCapabilities::Snapshot`
reports `multiple_windows == false` for UIKit canvas, UIKit controls, Android
canvas, and Android controls. Applications must query that capability rather
than infer multiwindow support from a desktop backend or OS name.

`start()` creates a session, `resize()`, `set_safe_area()`, and
`set_keyboard()` update facts without rebuilding application state, and
`surface_lost()`/`surface_restored()` preserve the session generation across a
new native surface. Focus and foreground/background facts may arrive before or
after those surface notifications; while the surface is absent they are staged
without enabling rendering or input, then applied on restoration.
`background()` suspends input and `foreground()` resumes it. The module contains
no Android, iOS, or native object references, so it can be used by device
adapters and deterministic headless tests alike.
