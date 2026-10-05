# Supported platforms and build requirements

This page states which elisa-ui API versions and platform profiles have direct
build or runtime evidence, and what toolchains each profile requires. A
successful cross-link is not a runtime test, and a policy-only test is not a
hosted product. Minimum OS and compiler versions are not promised unless a row
states one; the recorded versions below are tested reference tuples.

## Versioned public interfaces

| Interface | Current version | Compatibility contract |
| --- | --- | --- |
| Framework API (`UiBuild`) | 0.1.0 | A different major is incompatible. Minor and patch differences remain API-compatible and identify which side is newer. |
| C boundary (`include/elisa_ui.h`) | 1.2.0 | Packed as `0xMMmmpp`. A major mismatch is incompatible; additive controls advance the minor version. Hosts query `elisa_ui_abi_version()` before stateful calls. |
| Skia bridge (`include/elisa_skia.h`) | 0.7.0 | Hosts query the bridge version before passing opaque renderer objects. This is separate from both the framework API and C boundary versions. |
| WasmBrowser package profile | `wasmbrowser:component@1` | The manifest and the selected WasmBrowser CLI/SDK define the component contract. Native C ABI success does not establish WIT or component interoperability. |

The C, Rust, and Go bindings intentionally provide a tested retained-control
subset rather than every `UiHandles` operation. Their current documented
surface and lifecycle guarantees are in [Optional foreign-language
bindings](ui-bindings.md).

## Common compiler and host requirements

Build Elisa sources with the Stage1 compiler and runtime selected together by
[`scripts/resolve_stage1_root.sh`](../scripts/resolve_stage1_root.sh). Do not
combine a compiler product from one revision with a runtime object from
another. [`scripts/check_toolchain.sh`](../scripts/check_toolchain.sh) verifies
the selected product/runtime provenance and freshness before the focused
native gates.

The reference host tuple checked on 2026-10-05 was macOS 27.0.1 on arm64,
Xcode 27.0 (build 27A266a), and Homebrew clang 23.1.1. The current Stage1
source revision is `2691a64c7522c94eee0d5b0b930d1995c7376a3c`; its freshly
rebuilt product SHA-256 is
`a30ba6237db030cbe754f6b360f635b61903ba1154d5942870637b4e13546ff4`, with
matching runtime SHA-256
`b51e6114f0576681e432e1162a3dbdcdac46c140d3b7e7256c0069be0bd11897`. The
focused Android package gate used this compiler product with
`ELISA_ALLOW_DIRTY_STAGE1=1`; the checkout's generated provenance check passes.
The separate retained-tree performance samples retain their exact compiler
tuple in the [dated validation note](implementation-baseline/validation-2026-10-05.md).
The same host had iOS device and simulator SDK 27.0, SDL3 3.4.16, SDL3_ttf
3.2.2, GTK 4.24.0, Rust 1.98.1, and Go 1.27.1. The C API gate also passes
with the default selected Xcode developer directory on this tuple.

These values are an observed build tuple, not declared minimums. For Linux,
Android, Windows, Skia, and WasmBrowser, the required external SDKs and the
scope of each validation are listed below and in the more detailed
[backend and feature matrix](implementation-baseline/backend-and-feature-matrix.md).

## Native standalone versus hosted component

Native standalone rows below own a platform window or view through the listed
backend. `wasmbrowser:component@1` is a separate hosted profile: it is neither
a browser-DOM backend nor a native standalone backend. Native evidence on an
OS does not establish WasmBrowser host availability there, and a component
runtime smoke does not establish native-window support.

| OS target | Native standalone evidence | WasmBrowser-hosted evidence |
| --- | --- | --- |
| macOS | SDL3, AppKit, and GTK; Skia when the pinned SDK is supplied. | Component WIT compilation/validation and SDK guest-smoke evidence use the configured host tuple; UI `.wapp` packaging and host-window launch are unverified. |
| Linux | SDL3 and GTK; portable framework tests run on Linux. | No Linux-specific WasmBrowser host/window launch is claimed. |
| Windows | Win32 controls cross-compile and link; runtime execution is unverified. | No Windows-specific WasmBrowser host/window launch is claimed. |
| iOS | UIKit canvas and native controls build for simulator/device; simulator interaction is tested, physical-device acceptance remains open. | No iOS-hosted WasmBrowser app integration is claimed. |
| Android | Canvas and native controls build; Pixel_9 AVD interaction is tested, physical-device acceptance remains open. | No Android-hosted WasmBrowser app integration is claimed. |

## Backend and profile requirements

| Backend or profile | Build requirements | Evidence and support limits |
| --- | --- | --- |
| SDL3 native on macOS or Linux | Stage1 compiler/runtime, C toolchain, and the `sdl3` plus `sdl3-ttf` development packages discoverable through `pkg-config`. | `scripts/run_tests.sh` and the SDL-focused fixtures exercise native behavior. SDL3 is tested on macOS and Linux; Linux evidence uses the repository's Linux runner. This does not imply pixel identity with Apple text rendering. |
| AppKit native controls | macOS host, Xcode/macOS SDK, AppKit, and Foundation. | `scripts/check_appkit.sh` builds and exercises native controls. AppKit is a macOS-only backend. |
| AppKit custom canvas | macOS host, Xcode/macOS SDK, AppKit, Foundation, CoreGraphics, and CoreText. | `scripts/check_appkit_canvas.sh` builds and exercises off-screen rendering. AppKit is a macOS-only backend. |
| Skia custom painter | Pinned source/build from [`third_party/skia.lock`](../third_party/skia.lock), a matching target/compiler archive, and `SKIA_ROOT`; AppKit Skia additionally requires the macOS SDK. | Strict Skia gates require the pinned archive and fail when it is absent. CPU-raster macOS fixtures are tested; Android canvas builds and AVD evidence are recorded separately. GPU/Metal parity is not implied. |
| UIKit canvas and native controls | macOS build host with Xcode's iOS device and simulator SDKs; simulator execution requires an installed iOS runtime. Device packaging also requires the signing setup used by the build script. | `scripts/check_uikit.sh` builds simulator and device images; focused simulator gates exercise lifecycle, touch, text, and controls. The 2026-10-04 simulator acceptance used iOS 26.5; physical-device acceptance remains open. |
| Android canvas | Android SDK and NDK plus a pinned Android Skia build supplied through `SKIA_ROOT`/`SKIA_ANDROID_OUT`; a connected device or AVD is required for runtime evidence. | `scripts/check_android.sh` verifies the ARM64 package and, when a device is attached, installs it and checks rendered output. The recorded runtime fixture is a Pixel_9 Android 37.1 AVD; physical-device acceptance remains open. |
| Android native controls | Android SDK/NDK and the Java/JNI build tools used by `scripts/check_android_controls.sh`; the device half runs only when an AVD or device is attached. | The package, exports, storage alignment, and host/JNI contract are checked. Runtime/device coverage is conditional and must not be inferred from a package-only pass. |
| GTK native controls | GTK 4 development headers and libraries, `pkg-config`, and a display server. GTK 4.14 or newer is required for the accessible-text privacy adapter; Linux headless execution uses Xvfb. | `scripts/check_gtk.sh` and `scripts/check_gtk_linux.sh` exercise macOS GTK 4.24 and Linux GTK 4.22. Live screen-reader acceptance remains open. |
| Win32 native controls | `x86_64-w64-mingw32-gcc`/binutils and Windows target headers, plus the Stage1 compiler's Windows target support. | `scripts/check_win32.sh` cross-compiles and links a PE32+ image and checks both sides of the ABI. There is no Windows runtime or Narrator evidence in this matrix. |
| WasmBrowser hosted component | Stage1 component compilation, the matching wasm-sdk bindings/WIT world, WasmBrowser CLI component and runtime. `scripts/check_wapp.sh` accepts explicit checkout/tool paths through `ELISA_UI_WASM_SDK`, `ELISA_UI_WASMBROWSER`, `ELISA_UI_WIT`, `WASM_BROWSER_CLI`, and `WASMBROWSER_ELISA_CLI_COMPONENT`. | UI component compilation and WIT validation are distinct from `.wapp` packaging or hosted launch, which remain unverified on the current tuple. This profile is separate from the native C/Rust/Go ABI and still depends on the selected host/SDK contract. |
| Remote rendering/input | No remote transport or native presentation SDK is claimed by the policy layer. | `test/remote_test.elisa` validates negotiation and lifecycle policy only; a host transport and presentation adapter are separate work. |

See [current validation](implementation-baseline/current-validation.md) and
the [2026-10-05 validation note](implementation-baseline/validation-2026-10-05.md)
for dated gate results; see [known backend differences](implementation-baseline/backend-and-feature-matrix.md)
for behavior that is intentionally not pixel-identical or not yet runtime
verified.
