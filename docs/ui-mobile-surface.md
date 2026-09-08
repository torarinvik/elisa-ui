# Mobile surface facts

`UiMobileSurface` is the shared Elisa contract for Android and iOS adapters.
Adapters report logical viewport size, scale, safe-area edges, keyboard
occlusion, and surface recreation through this module while `UiLifecycle` owns
focus, background, and rendering eligibility. `snapshot()` derives the current
content area and orientation through `UiResponsive`.

`start()` creates a session, `resize()`, `set_safe_area()`, and
`set_keyboard()` update facts without rebuilding application state, and
`surface_lost()`/`surface_restored()` preserve the session generation across a
new native surface. `background()` suspends input and `foreground()` resumes it.
The module contains no Android, iOS, or native object references, so it can be
used by device adapters and deterministic headless tests alike.
