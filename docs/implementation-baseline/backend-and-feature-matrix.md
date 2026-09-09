# Backend and feature matrix

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._


| Backend/profile | Status | Evidence or limitation |
| --- | --- | --- |
| SDL3 native | implemented-tested | `scripts/run_tests.sh`; SDL keymap/text tests and dummy-video smoke path pass. |
| AppKit native controls | implemented-tested | `scripts/check_appkit.sh` creates and reads real NSWindow/NSView/control objects without ordering a window onscreen. |
| AppKit custom canvas | implemented-tested | `scripts/check_appkit_canvas.sh` builds/signs the app, renders an off-screen PNG, and exercises semantic-object identity and callbacks. |
| Skia custom painter | implemented-tested when the pinned SDK/archive is present; required gate | `scripts/build_skia.sh` reproduces the checkout/archive from `third_party/skia.lock`; strict `scripts/check_skia.sh` and `scripts/check_appkit_skia.sh` render headlessly and report pixel/timing evidence. This checkout intentionally does not vendor the multi-gigabyte SDK/build output, so a local run without `SKIA_ROOT` is an explicit non-passing dependency failure. |
| Optional feature view | implemented-tested at Elisa boundary; host activation integration planned | `test/feature_view_test.elisa` covers typed identity, activation tokens, stale polling, terminal failures, retry generations, cancellation, owner disposal, explicit view actions, back handling, and invalidation. The SDK/host remains responsible for actual component activation and deactivation. |
| WasmBrowser hosted | implemented-tested for fresh package/inspect; runtime launch planned | `ELISA_UI_STAGE1=../wasm-sdk-compiler bash scripts/build_wapp.sh hello` now emits and packs the component, and `scripts/check_wapp.sh` passes profile/import/export inspection. Runtime launch and device execution still need dedicated fixtures. |
| Android standalone | portable surface contract implemented; device fixture planned | `test/mobile_surface_test.elisa` verifies the shared Elisa surface/lifecycle policy. No Android build or device fixture exists in this checkout. |
| iOS standalone | portable surface contract implemented; device fixture planned | `test/mobile_surface_test.elisa` verifies the shared Elisa surface/lifecycle policy. No iOS build or device fixture exists in this checkout. |
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
