# Backend and feature matrix

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


| Backend/profile | Status | Evidence or limitation |
| --- | --- | --- |
| SDL3 native | implemented-tested on macOS **and Linux** | `scripts/run_tests.sh`; `sdl3_image_binding_test` and `sdl3_showcase_image_workflow_test` use SDL's dummy driver for retained-widget/showcase pixel readback, alongside SDL keymap/text tests. `scripts/check_core_linux.sh` runs the portable SDL tests on Linux, which is where this backend actually paints — and immediately found that its only default font path was a macOS one, so no font opened on Linux at all while ascent and line height quietly fell back to the requested point size. |
| The framework itself, on Linux | implemented-tested | `scripts/check_core_linux.sh` cross-compiles the portable corpus (66 of the 73 — all but the Apple-framework and Skia-host fixtures), links and runs it inside an OrbStack machine. Layout, text, state, identity, events and the SDL3 backend are exercised on a second operating system rather than inferred from one. |
| AppKit native controls | implemented-tested | `scripts/check_appkit.sh` creates and reads real NSWindow/NSView/control objects without ordering a window onscreen. |
| AppKit custom canvas | implemented-tested | `scripts/check_appkit_canvas.sh` builds/signs the app, renders an off-screen PNG, and exercises semantic-object identity and callbacks. |
| Skia custom painter | implemented-tested when the pinned SDK/archive is present; required gate | `scripts/build_skia.sh` reproduces the checkout/archive from `third_party/skia.lock`; strict `scripts/check_skia.sh` and `scripts/check_appkit_skia.sh` render headlessly and report pixel/timing evidence. This checkout intentionally does not vendor the multi-gigabyte SDK/build output, so a local run without `SKIA_ROOT` is an explicit non-passing dependency failure. |
| Optional feature view | implemented-tested at Elisa boundary; host activation integration planned | `test/feature_view_test.elisa` covers coalesced multi-owner activation leases, owner-scoped cancel/disposal, token-preserving tombstones and acknowledgements, stale polling, terminal failures, retry generations, explicit view actions, and back handling. The SDK/host remains responsible for actual component activation and deactivation. |
| Permission/picker services | implemented-tested at Elisa boundary; native adapter integration planned | `test/services_test.elisa` covers the consent and picker state machines, the anti-prompt gate after denial, `sync` on a settings change, logical selection identity, owner disposal, and staleness. Native permission/picker adapters still own the OS dialog and verified bytes. |
| WasmBrowser hosted | implemented-tested for fresh package/inspect and typed runtime smoke | `scripts/check_wapp.sh` builds the package from this tree, inspects its profile/imports/exports and JS-freeness, and drives the aligned SDK component through WasmBrowser `wb-runtime` guest start, frame, keyboard, pointer, and lifecycle callbacks. A full window/device launch and app-specific host presentation remain separate acceptance work. |
| UIKit custom canvas | implemented-tested | `scripts/check_uikit.sh` builds for the simulator and links a device image; `scripts/check_uikit_simulator.sh` runs it and reads back screenshots; `scripts/check_uikit_touch.sh` drives real touches. |
| UIKit native controls | implemented-tested | Real `UILabel`/`UIButton`/`UITextField`/`UISwitch` rows, measured with `systemLayoutSizeFittingSize:` and re-laid-out on Dynamic Type changes; same three gates. |
| Android custom canvas | implemented-tested on a device | `scripts/check_android.sh` cross-compiles, packages, reads the APK back, then installs and reads the frame trace off an attached device. `scripts/check_android_ime.sh` drives the real `InputConnection` and asserts a composing run arrives, is replaced, and commits. |
| Android native controls | implemented-tested (package gate; device half when attached) | `scripts/check_android_controls.sh` builds the Java/JNI `android.widget` product with the selected compiler, verifies its distinct Elisa/JNI symbols, absence of Skia/shared C++ dependencies, stored 16 KB-aligned native library and `hasCode="true"` APK, then launches and screenshots the real Activity when a device is attached. |
| GTK native controls | implemented-tested, on macOS **and on Linux** | `scripts/check_gtk.sh` builds live GtkWindows/GtkButtons/GtkEntries on macOS and asserts every cell of the seam's GTK column, plus colour as GTK resolved it and as GSK painted it. `scripts/check_gtk_linux.sh` runs the same fixture cross-compiled for Linux inside an OrbStack machine against a real X server, and fails rather than skips if it finds no display. |
| Win32 native controls | implemented, cross-compiled (never run here) | `scripts/check_win32.sh` cross-compiles both halves against real Windows headers, checks every symbol in both directions, and links a PE32+ image. The runtime's optional POSIX execution-trace names are supplied by the small Elisa-only `win32_debug_referee.elisa` adapter: `kill` can terminate the current process for the final fault re-raise, while `sigaction` reports unsupported rather than passing the three-argument POSIX handler to the one-argument Windows CRT callback. No Windows machine is available for execution evidence. |
| iOS/Android portable surface | implemented-tested | `test/mobile_surface_test.elisa` verifies the shared Elisa surface/lifecycle policy that all four mobile backends above sit on. |
| Remote rendering/input | implemented-tested at Elisa policy boundary; transport integration planned | `test/remote_test.elisa` covers typed-command/framebuffer/video negotiation, bounded scale conversion, lifecycle generations/overlays, and input sequencing/acknowledgements headlessly. A future WasmBrowser/SDK adapter still owns transport and presentation objects. |

The remote policy now rejects zero-sized negotiated surfaces and unaccepted
viewport conversions, while stale acknowledgements are surfaced diagnostically.
State snapshots reject non-finite float payloads on both save and restore, and
resource progress is monotonic within a generation; these guarantees are
covered by the focused remote, state, and resource fixtures.

Implemented-tested in the current native corpus: retained layout and dirty
relayout, responsive size classes/adaptive axes/bounded grid columns/safe-area
and keyboard-inset content boxes/orientation, bounded virtual-list ranges/content extents/semantic
windows, normalized min/preferred/max constraints, stable keyed identities,
typed widget lifetimes, hit testing and scrolling, control state, Unicode text
editing/IME and bounded undo history, shared themes/localization/RTL/plurals,
revision-safe async validation, bounded dialog ordering/results/semantics,
deterministic touch gesture classification, zero-safe touch identities,
explicit back-navigation allow/consume/confirm policy, scalar-safe text line breaking,
purpose-driven text-input/privacy traits, clipping and raster commands, C API
shape, AppKit semantics, and SDL/AppKit key maps. Implemented
but not yet device-verified: actual VoiceOver interaction, non-ASCII IMEs on a
physical device, and cross-scale font fallback. Secure text is intentionally
excluded from readback, semantic selected text, snapshots, and clipboard.

Known backend differences are intentional: SDL_ttf and CoreText are separate
font authorities; hosted text is measured by the WasmBrowser host; AppKit
accessibility is native while hosted/mobile adapters still need their own host
fixtures. Clipboard authority is SDL3, AppKit pasteboard, or WasmBrowser's
declared capability respectively, with byte-oriented Elisa adapters above each.
The hosted `key-code` enum also exposes `shift` and `control` but not `alt`, so
word-wise keyboard text navigation uses the Control convention there until
WasmBrowser widens the WIT vocabulary (WB-05); native SDL and the Apple
backends accept both Alt/Option and Control.
