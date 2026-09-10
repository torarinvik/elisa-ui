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
        target != nullptr && font_handle != 0 && text != nullptr && length > 0 && bounded_coordinate(x) &&
        bounded_coordinate(y) && bounded_extent(size)) {
        SkFont font = font_for(size, reinterpret_cast<SkTypeface *>(font_handle));
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font,
                               fill_paint(red, green, blue, alpha));
    }
}


extern "C" float elisa_skia_measure_text_width_with_font(std::size_t font_handle,
                                                           const char *text, std::size_t length,
                                                           float size) {
    if (font_handle == 0 || text == nullptr || length == 0 || !bounded_extent(size)) return 0.0f;
    const float measured = font_for(size, reinterpret_cast<SkTypeface *>(font_handle))
        .measureText(text, length, SkTextEncoding::kUTF8);
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
        target != nullptr && text != nullptr && length > 0 && bounded_coordinate(x) &&
        bounded_coordinate(y) && bounded_extent(size)) {
        const SkFont font = weighted_font_for(size, font_handle, weight_stroke);
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font,
                               weighted_paint(fill_paint(red, green, blue, alpha), weight_stroke));
    }
}


extern "C" float elisa_skia_measure_text_width_weighted(std::size_t font_handle,
                                                          const char *text, std::size_t length,
                                                          float size, float weight_stroke) {
    if (text == nullptr || length == 0 || !bounded_extent(size)) return 0.0f;
    const float measured = weighted_font_for(size, font_handle, weight_stroke)
        .measureText(text, length, SkTextEncoding::kUTF8);
    return finite(measured) && measured >= 0.0f ? measured : 0.0f;
}


extern "C" void elisa_skia_set_bold_typeface(std::size_t font) {
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
        target != nullptr && text != nullptr && length > 0 && bounded_coordinate(x) && bounded_coordinate(y) &&
        bounded_extent(size)) {
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font_for(size),
                               fill_paint(red, green, blue, alpha));
    }
}


extern "C" float elisa_skia_measure_text_width(const char *text, std::size_t length, float size) {
    if (text == nullptr || length == 0 || !bounded_extent(size)) return 0.0f;
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
