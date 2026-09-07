// Narrow C ABI for the Elisa Skia painter.
//
// The custom renderer never exposes SkCanvas, SkPaint, or SkFont through the
// Elisa ABI. A host owns the surface and passes one borrowed SkCanvas* for the
// duration of a frame; every primitive below validates that opaque handle
// before messaging Skia. Build this file only in a target that provides Skia.

#include <cstddef>
#include <cstdint>

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFont.h"
#include "include/core/SkPaint.h"
#include "include/core/SkRect.h"
#include "include/core/SkPath.h"

namespace {

SkCanvas *canvas(std::size_t handle) {
    return reinterpret_cast<SkCanvas *>(handle);
}

SkColor color(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    return SkColorSetARGB(alpha, red, green, blue);
}

SkPaint fill_paint(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setStyle(SkPaint::kFill_Style);
    paint.setColor(color(red, green, blue, alpha));
    return paint;
}

SkPaint stroke_paint(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    SkPaint paint = fill_paint(red, green, blue, alpha);
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(1.0f);
    return paint;
}

SkFont font_for(float size) {
    SkFont font;
    font.setSize(size > 0.0f ? size : 1.0f);
    font.setEdging(SkFont::Edging::kAntiAlias);
    return font;
}

}

extern "C" void elisa_skia_canvas_save(std::size_t handle) {
    if (SkCanvas *target = canvas(handle)) target->save();
}

extern "C" void elisa_skia_canvas_restore(std::size_t handle) {
    if (SkCanvas *target = canvas(handle)) target->restore();
}

extern "C" void elisa_skia_canvas_scale(std::size_t handle, float x, float y) {
    if (SkCanvas *target = canvas(handle)) target->scale(x, y);
}

extern "C" void elisa_skia_canvas_clip_rect(std::size_t handle, float x, float y, float width, float height) {
    if (SkCanvas *target = canvas(handle)) {
        target->clipRect(SkRect::MakeXYWH(x, y, width, height), SkClipOp::kIntersect, true);
    }
}

extern "C" void elisa_skia_canvas_clear(std::size_t handle, std::uint8_t red, std::uint8_t green,
                                         std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle)) target->clear(color(red, green, blue, alpha));
}

extern "C" void elisa_skia_canvas_fill_rect(std::size_t handle, float x, float y, float width, float height,
                                             std::uint8_t red, std::uint8_t green, std::uint8_t blue,
                                             std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle)) {
        target->drawRect(SkRect::MakeXYWH(x, y, width, height), fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_fill_circle(std::size_t handle, float x, float y, float radius,
                                                std::uint8_t red, std::uint8_t green, std::uint8_t blue,
                                                std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle)) {
        target->drawCircle(x, y, radius, fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_fill_triangle(std::size_t handle, float ax, float ay, float bx, float by,
                                                 float cx, float cy, std::uint8_t red, std::uint8_t green,
                                                 std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle)) {
        SkPath path;
        path.moveTo(ax, ay);
        path.lineTo(bx, by);
        path.lineTo(cx, cy);
        path.close();
        target->drawPath(path, fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_fill_line(std::size_t handle, float x0, float y0, float x1, float y1,
                                              std::uint8_t red, std::uint8_t green, std::uint8_t blue,
                                              std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle)) {
        target->drawLine(x0, y0, x1, y1, stroke_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_draw_text(std::size_t handle, const char *text, std::size_t length,
                                              float x, float y, float size, std::uint8_t red,
                                              std::uint8_t green, std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle); target != nullptr && text != nullptr && length > 0) {
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font_for(size),
                               fill_paint(red, green, blue, alpha));
    }
}

extern "C" float elisa_skia_measure_text_width(const char *text, std::size_t length, float size) {
    if (text == nullptr || length == 0) return 0.0f;
    return font_for(size).measureText(text, length, SkTextEncoding::kUTF8);
}

extern "C" float elisa_skia_font_ascent(float size) {
    SkFontMetrics metrics;
    font_for(size).getMetrics(&metrics);
    return -metrics.fAscent;
}

extern "C" float elisa_skia_text_line_height(float size) {
    SkFontMetrics metrics;
    font_for(size).getMetrics(&metrics);
    return metrics.fDescent - metrics.fAscent + metrics.fLeading;
}
