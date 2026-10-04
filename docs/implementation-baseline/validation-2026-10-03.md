# Focused validation follow-up — 2026-10-03

This records current-state evidence for the retained semantic-node work and the
compiler shadow check. It is incremental evidence, not full UI-06 acceptance.

## Source and toolchain tuple

- elisa-ui: HEAD `ecf40d80a77acd065e6dbe7e37b4bc605934cf63`, `main`, dirty
  worktree. Existing user changes were preserved.
- Host: macOS 27.0.1, Darwin 27.0.0, arm64.
- Stage1 compiler: clean `main` at `b903bd1e700aa2acda4925b59efd1ee60389431a`;
  product SHA-256 `734fad7984b0c6de3b50e6d57585e3c8573f975c33e4560f647a1209f9ed828d`,
  runtime SHA-256 `0db509f791ec1b075049dadc51a44f6e51e93e7c8fa9e6db4acbc336b7de022e`.
- Android compile tools: SDK platform `android-37.0`, NDK `30.0.16138531`,
  target `aarch64-linux-android30`.
- Adjacent hosted contracts inspected read-only: WasmBrowser `5a43c56a8bce9e42b6baab6cdbc84093f55ddd33` and wasm-sdk
  `5504e02b4809ef1d7723a603087d8f8882dcf1ac`.

## Retained semantics and Android adapter

- `accessibility_metadata_test` builds, links, and passes, including the
  regression where action target `4294967297` must normalize to the no-action
  sentinel instead of truncating to widget target `1`.
- `accessibility_geometry_test`, `dialog_test`, and `widget_layout_scroll_test`
  build and exit successfully; the latter two report all checks passed.
- `appkit_canvas_keymap_test` builds, links, and passes its focused assertions
  for retained semantic notifications, selection/value updates, geometry, and
  relationship changes.
- `scripts/check_android_accessibility_wire.sh` passes 11 host-JVM assertions,
  including malformed UTF-8, invalid hierarchy, and password text/caret
  rejection.
- All `src/platform/android/java/org/elisa_ui/*.java` sources compile against
  the SDK platform jar. `android_accessibility.cpp` compiles with the NDK using
  C++17, `-Wall -Wextra -Werror`, and `-Wno-unused-parameter`.
- `examples/storefront/android_main.elisa` cross-compiles to an Android API 30
  arm64 object. `check_source_sizes.sh`, `check_global_names.sh`,
  `git diff --check`, and `check_toolchain.sh --report` pass.
- `scripts/check_android.sh storefront` skips because `SKIA_ROOT` is unset.
  These host checks do not establish APK linking, device hierarchy, TalkBack,
  or physical keyboard acceptance.

## Compiler continuation check and hosted-binding gate

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash
  test/parity/struct_field_refinement_shadow_smoke.sh` passes against the
  selected Stage0/Stage1 pair. It accepts valid block/assignment/loop/match
  shadows and diagnoses the unrefined by-value parameter after its shadow
  scope closes.
- Hosted binding migration remains gated. At the inspected SDK revision,
  `render_buffer.elisa` encodes command tags 0–5, while elisa-ui emits image
  tag 6. The typed accessibility WIT record still omits UI revision, selection,
  numeric range, and collection-position fields. The local encoder remains
  necessary until the public SDK contract and host conformance gates cover the
  complete UI payload.

## Native-control sensitivity continuation

- `controls_flat_test` passes after adding assertions that the retained
  sensitivity marker reaches native `ControlState` and that both enabling and
  clearing it reapply help/placeholder state during reconciliation.
- `check_android_controls.sh showcase` passes on the same pinned Stage1
  product. The Showcase APK has the expected JNI exports, is stored and
  16-KiB-aligned, and its compiled Java surface contains the expanded
  `setState` descriptor and sensitive accessibility delegate calls. No Android
  device was attached, so the optional launch/screenshot check did not run.
- Source-size, global-name, and `git diff --check` gates pass after this change.
  These host/package checks do not establish TalkBack behavior or physical
  device privacy acceptance; other native-control adapters and diagnostic
  screenshot/trace redaction also remain open.
