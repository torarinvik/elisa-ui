#pragma once

bool same_pixels(SkSurface* first, SkSurface* second, const char* label) {
    SkPixmap first_pixels;
    SkPixmap second_pixels;
    if (!first->peekPixels(&first_pixels) || !second->peekPixels(&second_pixels) ||
        first_pixels.width() != second_pixels.width() ||
        first_pixels.height() != second_pixels.height()) {
        std::fprintf(stderr, "%s: could not inspect matching raster surfaces\n", label);
        return false;
    }
    for (int y = 0; y < first_pixels.height(); ++y) {
        for (int x = 0; x < first_pixels.width(); ++x) {
            if (first_pixels.getColor(x, y) != second_pixels.getColor(x, y)) {
                std::fprintf(stderr, "%s: raster mismatch at (%d,%d)\n", label, x, y);
                return false;
            }
        }
    }
    return true;
}

void draw_simple_text_reference(SkCanvas* target, const SkFont& base, SkTypeface* lent,
                                const char* text, std::size_t length,
                                const SkPaint& paint, float x, float y) {
    float pen = x;
    for (const elisa_skia_shim::TextRun& run : elisa_skia_shim::split_runs(lent, text, length)) {
        SkFont font = base;
        if (run.face) font.setTypeface(run.face);
        const std::size_t count = run.end - run.begin;
        target->drawSimpleText(text + run.begin, count, SkTextEncoding::kUTF8,
                               pen, y, font, paint);
        pen += font.measureText(text + run.begin, count, SkTextEncoding::kUTF8);
    }
}

bool test_simple_text_cache(SkTypeface* typeface, SkTypeface* alternate_typeface,
                            SkTypeface* fallback_test_typeface) {
    using namespace elisa_skia_shim;
    constexpr char text[] = "Cache parity";
    set_simple_text_cache_context(17, 9);
    clear_simple_text_cache();
    const SkFont font = font_for(24.0f, typeface);
    ElisaSimpleTextLayout uncached;
    const std::uint64_t misses_before = elisa_skia_simple_text_cache_misses;
    const ElisaSimpleTextLayout* first = simple_text_layout_for(
        font, typeface, text, sizeof(text) - 1, uncached);
    if (first == nullptr || first->advance <= 0.0f ||
        elisa_skia_simple_text_cache_misses != misses_before + 1) {
        std::fprintf(stderr, "skia simple-text cache: initial layout was not cached\n");
        return false;
    }
    const std::uint64_t hits_before = elisa_skia_simple_text_cache_hits;
    const ElisaSimpleTextLayout* repeated = simple_text_layout_for(
        font, typeface, text, sizeof(text) - 1, uncached);
    if (repeated == nullptr || repeated->advance != first->advance ||
        elisa_skia_simple_text_cache_hits != hits_before + 1) {
        std::fprintf(stderr, "skia simple-text cache: identical font/text query missed\n");
        return false;
    }

    // Draw-time paint is deliberately outside the cache key. Compare the
    // cached blob against the existing simple-text API at fractional origin,
    // first in white and then with a different color.
    const SkImageInfo info = SkImageInfo::Make(
        180, 52, kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    for (const SkColor color : {SK_ColorWHITE, SkColorSetRGB(40, 210, 90)}) {
        sk_sp<SkSurface> cached_surface = SkSurfaces::Raster(info);
        sk_sp<SkSurface> direct_surface = SkSurfaces::Raster(info);
        if (!cached_surface || !direct_surface) {
            std::fprintf(stderr, "skia simple-text cache: failed to create parity surfaces\n");
            return false;
        }
        cached_surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        direct_surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        SkPaint paint = fill_paint(SkColorGetR(color), SkColorGetG(color),
                                   SkColorGetB(color), SkColorGetA(color));
        draw_simple_text_layout(cached_surface->getCanvas(), *repeated, paint, 7.25f, 38.0f);
        draw_simple_text_reference(direct_surface->getCanvas(), font, typeface,
                                   text, sizeof(text) - 1, paint, 7.25f, 38.0f);
        if (!same_pixels(cached_surface.get(), direct_surface.get(),
                         "skia simple-text blob parity")) return false;
    }

    if (fallback_test_typeface != nullptr) {
        constexpr char fallback_text[] = "\xE2\x8C\x98 K"; // U+2318 is absent from Helvetica.
        const auto fallback_runs = split_runs(
            fallback_test_typeface, fallback_text, sizeof(fallback_text) - 1);
        if (fallback_runs.size() < 2) {
            std::fprintf(stderr, "skia simple-text cache: fixture did not select a fallback face\n");
            return false;
        }
        const SkFont fallback_font = font_for(24.0f, fallback_test_typeface);
        const ElisaSimpleTextLayout* fallback_layout = simple_text_layout_for(
            fallback_font, fallback_test_typeface, fallback_text,
            sizeof(fallback_text) - 1, uncached);
        if (fallback_layout == nullptr || fallback_layout->runs.size() != fallback_runs.size()) {
            std::fprintf(stderr, "skia simple-text cache: fallback run layout did not match\n");
            return false;
        }
        sk_sp<SkSurface> cached_surface = SkSurfaces::Raster(info);
        sk_sp<SkSurface> direct_surface = SkSurfaces::Raster(info);
        if (!cached_surface || !direct_surface) return false;
        cached_surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        direct_surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        SkPaint paint = fill_paint(250, 230, 80, 255);
        draw_simple_text_layout(cached_surface->getCanvas(), *fallback_layout,
                                paint, 7.25f, 38.0f);
        draw_simple_text_reference(direct_surface->getCanvas(), fallback_font,
                                   fallback_test_typeface, fallback_text,
                                   sizeof(fallback_text) - 1, paint, 7.25f, 38.0f);
        if (!same_pixels(cached_surface.get(), direct_surface.get(),
                         "skia simple-text fallback parity")) return false;
    }

    const std::uint64_t font_misses_before = elisa_skia_simple_text_cache_misses;
    (void)simple_text_layout_for(font_for(25.0f, typeface), typeface,
                                 text, sizeof(text) - 1, uncached);
    (void)simple_text_layout_for(font, typeface, "Different text", 14, uncached);
    if (elisa_skia_simple_text_cache_misses != font_misses_before + 2) {
        std::fprintf(stderr, "skia simple-text cache: font or exact-text key was ignored\n");
        return false;
    }
    constexpr char counted_text[] = {'C', 'a', 'c', 'h', 'e', '\0', 'x'};
    const std::uint64_t counted_misses_before = elisa_skia_simple_text_cache_misses;
    (void)simple_text_layout_for(font, typeface, counted_text,
                                 sizeof(counted_text), uncached);
    const std::uint64_t counted_hits_before = elisa_skia_simple_text_cache_hits;
    (void)simple_text_layout_for(font, typeface, counted_text,
                                 sizeof(counted_text), uncached);
    if (elisa_skia_simple_text_cache_hits != counted_hits_before + 1 ||
        elisa_skia_simple_text_cache_misses != counted_misses_before + 1) {
        std::fprintf(stderr, "skia simple-text cache: counted text with an embedded NUL was truncated\n");
        return false;
    }
    if (alternate_typeface != nullptr) {
        const std::uint64_t face_misses_before = elisa_skia_simple_text_cache_misses;
        (void)simple_text_layout_for(font_for(24.0f, alternate_typeface), alternate_typeface,
                                     text, sizeof(text) - 1, uncached);
        if (elisa_skia_simple_text_cache_misses != face_misses_before + 1) {
            std::fprintf(stderr, "skia simple-text cache: typeface identity was ignored\n");
            return false;
        }
    }

    set_simple_text_cache_context(18, 9);
    if (!elisa_skia_simple_text_cache.empty()) {
        std::fprintf(stderr, "skia simple-text cache: locale revision did not invalidate entries\n");
        return false;
    }
    (void)simple_text_layout_for(font, typeface, text, sizeof(text) - 1, uncached);
    set_simple_text_cache_context(18, 10);
    if (!elisa_skia_simple_text_cache.empty()) {
        std::fprintf(stderr, "skia simple-text cache: scale generation did not invalidate entries\n");
        return false;
    }
    const std::size_t manager = elisa_skia_font_manager;
    elisa_skia_set_font_manager(0);
    if (!elisa_skia_simple_text_cache.empty()) {
        std::fprintf(stderr, "skia simple-text cache: font-manager change did not invalidate entries\n");
        return false;
    }
    elisa_skia_set_font_manager(manager);
    (void)simple_text_layout_for(font, typeface, text, sizeof(text) - 1, uncached);
    elisa_skia_set_text_quality(1, 2);
    if (!elisa_skia_simple_text_cache.empty()) {
        std::fprintf(stderr, "skia simple-text cache: text-quality change did not invalidate entries\n");
        return false;
    }
    elisa_skia_set_text_quality(0, 0);

    set_simple_text_cache_context(0, 0);
    for (std::size_t index = 0; index < 72; ++index) {
        const SkFont sized = font_for(8.0f + static_cast<float>(index), typeface);
        (void)simple_text_layout_for(sized, typeface, text, sizeof(text) - 1, uncached);
    }
    if (elisa_skia_simple_text_cache.size() != max_simple_text_cache_entries ||
        elisa_skia_simple_text_cache_bytes > max_simple_text_cache_bytes) {
        std::fprintf(stderr, "skia simple-text cache: entry or byte bound was exceeded\n");
        return false;
    }

    clear_simple_text_cache();
    char large_text[900];
    std::memset(large_text, 'm', sizeof(large_text));
    for (std::size_t index = 0; index < 18; ++index) {
        const SkFont sized = font_for(12.0f + static_cast<float>(index), typeface);
        (void)simple_text_layout_for(sized, typeface, large_text, sizeof(large_text), uncached);
    }
    if (elisa_skia_simple_text_cache.size() >= 18 ||
        elisa_skia_simple_text_cache_bytes > max_simple_text_cache_bytes) {
        std::fprintf(stderr, "skia simple-text cache: byte-cost LRU bound was not enforced\n");
        return false;
    }

    char oversized[1024];
    std::memset(oversized, 'x', sizeof(oversized));
    const std::size_t entries_before_oversized = elisa_skia_simple_text_cache.size();
    (void)simple_text_layout_for(font, typeface, oversized, sizeof(oversized), uncached);
    if (elisa_skia_simple_text_cache.size() != entries_before_oversized || uncached.runs.empty()) {
        std::fprintf(stderr, "skia simple-text cache: oversized layout was retained or lost\n");
        return false;
    }
    clear_simple_text_cache();
    return true;
}
