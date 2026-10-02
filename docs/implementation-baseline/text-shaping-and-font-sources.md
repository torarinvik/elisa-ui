# Text shaping and font-source evaluation

_Part of the [elisa-ui implementation baseline](../implementation-baseline.md)._

This is a source-level capability and licensing review, not a claim that every
profile passes complex-script rendering. Text metrics and drawing remain
profile-owned; a shared width function does not make shaping behavior equal.

| Profile | Current text authority | Script and fallback assessment | Dependency/font-source notes |
| --- | --- | --- | --- |
| AppKit / UIKit | CoreText (`CTLine` construction and drawing) | Uses the OS text stack, including Unicode-to-glyph layout and font cascading. The current fixture set does not yet certify mixed-direction pixel output across OS releases or device fallback fonts. | CoreText is an OS framework, not an application-bundled font library. System font availability and behavior are OS-owned. |
| SDL3 | SDL_ttf `TTF_GetStringSize` and `TTF_RenderText_Blended` | The adapter sets per-font RTL direction, active complete BCP47 locale as language, and an explicit ISO 15924 script subtag for both measurement and rasterization; it restores LTR/no-language/no-script on the cached face. `sdl3_text_test` checks these state transitions and Arabic measurement. Script autodetection for mixed-script runs and explicit font fallback policy remain unimplemented; mixed-bidi run reordering and rendered Arabic/Indic acceptance remain open. | SDL_ttf is zlib-licensed; its documented dependencies include FreeType (FTL or GPLv2) and HarfBuzz (MIT), though HarfBuzz support is build-configurable. Candidate font files are not covered by those library licenses. The adapter does not bundle the discovered system fonts. |
| Skia custom painter | On Apple, untracked text uses Skia's `SkShaper::MakeCoreText` module to shape a complete string into positioned runs; the same shaped advances/blob serve measurement/drawing. Android and tracked text retain `SkFont::measureText`/`drawSimpleText` and per-codepoint fallback. | Apple CoreText smoke tests render Arabic and Devanagari ink and verify measured coverage, but do not certify mixed-bidi ordering, language-sensitive forms, or full Indic shaping. The pinned CoreText shaper ignores the supplied bidi/script/language iterators; fallback is OS/CoreText-owned. Android has no active shaper. | Skia and its `modules/skshaper` are BSD-3-Clause; the pinned build still disables HarfBuzz. AppKit lends system typefaces; no font files are bundled. |
| WasmBrowser hosted | Host `measure-text-width` plus host rendering of the transmitted text command | The host owns shaping, font fallback, and visual order. The UI's Unicode/grapheme editing tests validate guest-side offsets, not host glyph layout. Host capability/renderer acceptance is still required for complex scripts. | The guest introduces no text engine or font files; dependency and font licensing belong to the selected host/runtime. |

Font policy: the framework may use platform-discovered fonts or a caller-owned
override path, but does not copy, package, or redistribute fonts found on the
machine. In particular, a familiar font family name or a system path is not a
redistribution grant; applications that ship font files must verify each
file's own license and notices independently of SDL_ttf, FreeType, HarfBuzz,
or Skia.

## Decision and remaining acceptance

Keep per-profile text authorities (D-2); do not introduce a single shared
shaper or promise identical advances. Preserve the current allocation-free
Elisa line-break/grapheme policy and require each painter/metric provider to
use the same shaped result for drawing, measurement, hit testing, selection,
and caret geometry.

The source audit identifies two concrete implementation gaps before this
requirement can be closed:

1. Add Unicode-script segmentation and explicit fallback policy, then verify
   rendered Arabic, Indic, and mixed-bidi output. SDL_ttf receives explicit
   locale script subtags, active BCP47 language, and first-strong direction
   for both measurement and draw; locale changes invalidate the shared width
   cache. A single locale script is not sufficient for mixed-script text.
2. Extend and certify Skia shaping across profiles. Apple now uses the pinned
   CoreText `SkShaper` module for ordinary, untracked text, with measurement
   and drawing derived from the same shaped run; Android and tracked text
   still use simple text APIs. CoreText's pinned adapter ignores the explicit
   bidi/script/language iterators, and fallback remains OS-owned. The current
   Arabic/Devanagari smoke is not mixed-script acceptance.

Add rendered/metric acceptance cases for Arabic joining, Hebrew mixed with
Latin and digits, Indic conjuncts, combining marks, ligatures, and emoji
fallback. Compare grapheme-safe hit-test/caret positions against the same
shaped visual runs. Run them on real SDL_ttf/CoreText/Skia backends and at
least one WasmBrowser host; the existing Unicode 15.1 grapheme corpus remains
necessary but is not a shaping test.

## Focused SDL evidence (2026-10-01)

`UiSdl3Fonts` scopes `TTF_SetFontDirection`, `TTF_SetFontLanguage`, and
`TTF_SetFontScript` around both `TTF_GetStringSize` and
`TTF_RenderText_Blended`, and restores LTR/no-language/no-script on the cached
face after each run. It obtains an explicit script from a four-letter BCP47
subtag such as `Latn`; locale changes also reset
`UiTextMetrics`; `localization_test` covers cache refill after a locale
transition. `sdl3_text_test` compiled, linked, and passed
against SDL 3.4.16 and SDL_ttf 3.2.2 using the default Xcode 27.0 linker,
without a `DEVELOPER_DIR` override. It used Stage1 revision
`3fa4a7e590c3ae5919b759a85dc8f1e105246c8b` (product SHA-256
`4b36ce5a7dcf4c448ee037dce4ec393b603ed90d15aa534a90ee3888be8e83fe`; runtime
SHA-256 `4a25cda85e118d59355bc437cb4e6ca15cbd96212d861198dc003bb3a3d733cb`)
with `ELISA_ALLOW_DIRTY_STAGE1=1`. The fixture verifies per-font direction,
script, and language application/reset, plus Arabic measurement;
`localization_test` verifies locale-revision cache invalidation. These are not
rendered-pixel proofs; mixed-bidi, script segmentation/fallback, and Indic
cases remain open.

## Focused Skia evidence (2026-10-01)

The Apple shim now links Skia's `//modules/skshaper:skshaper` and uses its
CoreText implementation for ordinary, untracked text. `ElisaShapedTextHandler`
builds a positioned `SkTextBlob`; the handler's advances also supply width
measurement, so these two paths consume the same shaped result. A host-lent
font manager supplies Skia's font-run iterator, and CoreText provides the
system cascade. Tracked text and non-Apple builds continue through the simple
per-scalar path. Skia's pinned CoreText adapter currently ignores the bidi,
script, and language iterators passed to it, so this is not a mixed-run or
language-specific shaping guarantee.

The Apple bridge reuses these positioned blobs through a bounded LRU (64
entries, 1 MiB estimated cost). Its key includes exact text, full `SkFont`
attributes and typeface unique ID, fallback-manager identity, locale revision,
and scale generation. Locale/scale changes, text-quality or manager changes,
bold-face replacement, and surface loss invalidate it; large individual blobs
bypass the cache. The off-screen fixture verifies repeated-query hits,
locale/scale invalidation, and entry/estimated-byte bounds. The fixture also
calls the real `UiSkia::surface_lost()` path and asserts that its shaped entries
are retired. The actual end-to-end performance benefit remains unmeasured, and
no image cache is claimed.

Skia revision `9c7b2dffb2433f5a0cc2b77f06025a09126807ed` built against the
current Xcode 27 SDK with the default linker (no `DEVELOPER_DIR` override).
The provenance-verified `libskia.a` SHA-256 is
`61e3d7972bd25567c8dc14f5c310a3094ac0f6dbbee0d0d51275258fc0e71f19`; the
separate `libskshaper.a` SHA-256 is
`b68ffce9df1fa947efd4e8715d57621c372ed2af4c6b8c13784f671f0b454f9f`.
`check_skia_offscreen.sh` passes Arabic (`سلام`) and Devanagari (`नमस्ते`)
measurement/ink checks, 16 replays, and a fresh-process digest
`b0984af8b67497a4`. `check_showcase_skia.sh` passes its public workflow,
resource-generation transition, pixel assertions, 16 stable replays, and
fresh-process digest `f46a43a190df81cd`.

The broader `check_skia.sh` and `check_appkit_skia.sh` currently stop at
Stage1 code generation for `examples/showcase/appkit_skia_canvas_main.elisa`
(`view@23019`, call expression); the Hello AppKit/Skia entry compiles, but
the AppKit compositor host fixture is not reached by that gate. Both focused
Skia rendering gates above do pass with the same current compiler/Skia tuple.
An isolated link attempt using that host fixture's listed objects also found
undefined `_elisa_appkit_canvas_*` callbacks referenced by the Objective-C
bridge; the official gate has not reached this link step yet.
The independent all-pages `render_showcase_skia.sh` gate also stops before
linking: Stage1 declines `test/showcase_app_skia_test.elisa` at
`view@17988` (call expression). The gates above use
`ELISA_ALLOW_DIRTY_STAGE1=1` because the sibling Stage1 checkout contains
ongoing changes.

## Primary references

- [SDL_ttf overview and dependencies](https://wiki.libsdl.org/SDL3_ttf/FrontPage), [text rendering](https://wiki.libsdl.org/SDL3_ttf/TTF_RenderText_Blended), [per-font direction](https://wiki.libsdl.org/SDL3_ttf/TTF_SetFontDirection), [per-font script](https://wiki.libsdl.org/SDL3_ttf/TTF_SetFontScript), [per-font language](https://wiki.libsdl.org/SDL3_ttf/TTF_SetFontLanguage), and [fallback font API](https://wiki.libsdl.org/SDL3_ttf/TTF_AddFallbackFont).
- [FreeType license options](https://freetype.org/license.html) and [Skia license](https://github.com/google/skia/blob/main/LICENSE).
- [Skia text-shaping guidance](https://skia.org/docs/user/tips/) and [Apple Core Text](https://developer.apple.com/documentation/CoreText).
