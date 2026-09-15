// Narrow C ABI for the Elisa Skia painter: the TEXT half.
//
// Split from the canvas primitives when the single file outgrew the source
// budget. The seam is a real one: everything here is a question about a FACE
// -- which one, how it is hinted, how wide a string comes out, how far the
// baseline sits from the top -- while the canvas half never names a font.
//
// The framework decides appearance and this bridge obeys: the stem growth for
// a weighted run is a number Elisa supplies, and a designed bold face is one
// the host lends. Neither is chosen here.

#include "skia_shim_common.h"

using namespace elisa_skia_shim;

extern "C" void elisa_skia_set_text_quality(int subpixel, int hinting) {
    elisa_skia_text_subpixel = subpixel != 0 ? 1 : 0;
    elisa_skia_text_hinting = hinting;
}


extern "C" void elisa_skia_canvas_draw_text_with_font(std::size_t canvas_handle,
                                                        std::size_t font_handle,
                                                        const char *text, std::size_t length,
                                                        float x, float y, float size,
                                                        std::uint8_t red, std::uint8_t green,
                                                        std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && font_handle != 0 && valid_utf8_text(text, length) && bounded_coordinate(x) &&
        bounded_coordinate(y) && bounded_extent(size)) {
        SkTypeface *lent = reinterpret_cast<SkTypeface *>(font_handle);
        draw_runs(target, font_for(size, lent), fill_paint(red, green, blue, alpha), lent, text, length, x, y);
    }
}


extern "C" float elisa_skia_measure_text_width_with_font(std::size_t font_handle,
                                                           const char *text, std::size_t length,
                                                           float size) {
    if (font_handle == 0 || !valid_utf8_text(text, length) || !bounded_extent(size)) return 0.0f;
    SkTypeface *lent = reinterpret_cast<SkTypeface *>(font_handle);
    const float measured = measure_runs(font_for(size, lent), lent, text, length);
    return finite(measured) && measured >= 0.0f ? measured : 0.0f;
}


extern "C" void elisa_skia_canvas_draw_text_weighted(std::size_t canvas_handle,
                                                       std::size_t font_handle,
                                                       const char *text, std::size_t length,
                                                       float x, float y, float size,
                                                       float weight_stroke,
                                                       std::uint8_t red, std::uint8_t green,
                                                       std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && valid_utf8_text(text, length) && bounded_coordinate(x) &&
        bounded_coordinate(y) && bounded_extent(size)) {
        const SkFont font = weighted_font_for(size, font_handle, weight_stroke);
        draw_runs(target, font, weighted_paint(fill_paint(red, green, blue, alpha), weight_stroke),
                  font.getTypeface(), text, length, x, y);
    }
}


// THE HALO: the same glyphs, blurred, drawn first. It follows the letterforms
// rather than boxing them, which is what lets a headline sit on a picture and
// a dark caption sit on glass. Sigma scales with the size so a small caption
// gets a tight halo and a display line a soft one.
extern "C" void elisa_skia_canvas_draw_text_halo(std::size_t canvas_handle, std::size_t font_handle,
                                                   const char *text, std::size_t length,
                                                   float x, float y, float size, float weight_stroke,
                                                   std::uint8_t red, std::uint8_t green,
                                                   std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && valid_utf8_text(text, length) && alpha != 0 && bounded_coordinate(x) &&
        bounded_coordinate(y) && bounded_extent(size)) {
        const SkFont font = weighted_font_for(size, font_handle, weight_stroke);
        SkPaint paint = weighted_paint(fill_paint(red, green, blue, alpha), weight_stroke);
        const float sigma = size * 0.09f + 0.6f;
        paint.setMaskFilter(SkMaskFilter::MakeBlur(kNormal_SkBlurStyle, sigma));
        // Two passes: the blur alone reads thin at small alpha, and a second
        // pass at the same alpha is cheaper and cleaner than raising it.
        draw_runs(target, font, paint, font.getTypeface(), text, length, x, y);
        draw_runs(target, font, paint, font.getTypeface(), text, length, x, y);
    }
}

extern "C" float elisa_skia_measure_text_width_weighted(std::size_t font_handle,
                                                          const char *text, std::size_t length,
                                                          float size, float weight_stroke) {
    if (!valid_utf8_text(text, length) || !bounded_extent(size)) return 0.0f;
    const SkFont font = weighted_font_for(size, font_handle, weight_stroke);
    const float measured = measure_runs(font, font.getTypeface(), text, length);
    return finite(measured) && measured >= 0.0f ? measured : 0.0f;
}


// Lend a font manager so a glyph the lent face lacks can be drawn with one
// that has it. Zero takes it back; the per-code-point cache goes with it,
// because its answers were the manager's.
extern "C" void elisa_skia_set_text_tracking(float tracking) {
    elisa_skia_text_tracking = std::isfinite(tracking) && tracking > 0.0f ? tracking : 0.0f;
}

extern "C" void elisa_skia_set_font_manager(std::size_t manager) {
    elisa_skia_font_manager = manager;
    elisa_skia_fallback_cache.clear();
}

// Does every code point in this string resolve to a real glyph -- on the lent
// face or on a fallback the manager can supply? This is the question a
// fixture can ask that a rendered pixel cannot: a box glyph has ink too.
extern "C" int elisa_skia_text_covers(std::size_t font_handle, const char *text, std::size_t length) {
    SkTypeface *lent = reinterpret_cast<SkTypeface *>(font_handle);
    if (lent == nullptr || !valid_utf8_text(text, length)) return 0;
    for (const TextRun &run : split_runs(lent, text, length)) {
        SkTypeface *face = run.face ? run.face.get() : lent;
        std::size_t index = run.begin;
        while (index < run.end) {
            const std::uint32_t code = decode_utf8(text, length, index);
            if (code >= 0x20 && face->unicharToGlyph(static_cast<SkUnichar>(code)) == 0) return 0;
        }
    }
    return 1;
}

// A bold face that is not bold is worse than none: with one in hand the
// renderer draws a weighted run with it AND withholds the synthetic stem
// growth, so a regular face lent as "bold" loses the weight twice over. That
// is exactly what CoreText hands back for the null family -- Helvetica at
// 400 for every style asked -- and every heading in the storefront was drawn
// at regular weight because of it. A face is kept only if it is at least
// semibold; anything lighter is refused and weight is synthesised as before.
extern "C" void elisa_skia_set_bold_typeface(std::size_t font) {
    const SkTypeface *face = reinterpret_cast<const SkTypeface *>(font);
    if (face != nullptr && face->fontStyle().weight() < SkFontStyle::kSemiBold_Weight) {
        elisa_skia_bold_typeface = 0;
        return;
    }
    elisa_skia_bold_typeface = font;
}


extern "C" std::size_t elisa_skia_bold_typeface_handle(void) {
    return elisa_skia_bold_typeface;
}


extern "C" float elisa_skia_font_ascent_with_font(std::size_t font_handle, float size) {
    if (font_handle == 0 || !bounded_extent(size)) return 0.0f;
    SkFontMetrics metrics;
    font_for(size, reinterpret_cast<SkTypeface *>(font_handle)).getMetrics(&metrics);
    return finite(metrics.fAscent) ? -metrics.fAscent : 0.0f;
}


extern "C" float elisa_skia_text_line_height_with_font(std::size_t font_handle, float size) {
    if (font_handle == 0 || !bounded_extent(size)) return 0.0f;
    SkFontMetrics metrics;
    font_for(size, reinterpret_cast<SkTypeface *>(font_handle)).getMetrics(&metrics);
    const float height = metrics.fDescent - metrics.fAscent + metrics.fLeading;
    return finite(height) && height >= 0.0f ? height : 0.0f;
}


extern "C" void elisa_skia_canvas_draw_text(std::size_t handle, const char *text, std::size_t length,
                                              float x, float y, float size, std::uint8_t red,
                                              std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_utf8_text(text, length) && bounded_coordinate(x) && bounded_coordinate(y) &&
        bounded_extent(size)) {
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font_for(size),
                               fill_paint(red, green, blue, alpha));
    }
}


extern "C" float elisa_skia_measure_text_width(const char *text, std::size_t length, float size) {
    if (!valid_utf8_text(text, length) || !bounded_extent(size)) return 0.0f;
    const float measured = font_for(size).measureText(text, length, SkTextEncoding::kUTF8);
    return finite(measured) && measured >= 0.0f ? measured : 0.0f;
}


extern "C" float elisa_skia_font_ascent(float size) {
    if (!bounded_extent(size)) return 0.0f;
    SkFontMetrics metrics;
    font_for(size).getMetrics(&metrics);
    return finite(metrics.fAscent) ? -metrics.fAscent : 0.0f;
}


extern "C" float elisa_skia_text_line_height(float size) {
    if (!bounded_extent(size)) return 0.0f;
    SkFontMetrics metrics;
    font_for(size).getMetrics(&metrics);
    const float height = metrics.fDescent - metrics.fAscent + metrics.fLeading;
    return finite(height) && height >= 0.0f ? height : 0.0f;
}
