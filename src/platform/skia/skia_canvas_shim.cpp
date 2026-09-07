// Narrow C ABI for the Elisa Skia painter.
//
// The custom renderer never exposes SkCanvas, SkPaint, or SkFont through the
// Elisa ABI. A host owns the surface and passes one borrowed SkCanvas* for the
// duration of a frame; every primitive below validates that opaque handle
// before messaging Skia. Build this file only in a target that provides Skia.

#include <cstddef>
#include <cstdint>

#include "../../../include/elisa_skia.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFont.h"
#include "include/core/SkImage.h"
#include "include/core/SkPaint.h"
#include "include/core/SkRect.h"
#include "include/core/SkRRect.h"
#include "include/core/SkPath.h"
#include "include/core/SkSamplingOptions.h"
#include "include/core/SkTypeface.h"

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

SkPaint stroke_paint(std::uint8_t red, std::uint8_t green, std::uint8_t blue, std::uint8_t alpha,
                     float width) {
    SkPaint paint = fill_paint(red, green, blue, alpha);
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(width);
    return paint;
}

SkFont font_for(float size) {
    SkFont font;
    font.setSize(size > 0.0f ? size : 1.0f);
    font.setEdging(SkFont::Edging::kAntiAlias);
    return font;
}

SkFont font_for(float size, SkTypeface *typeface) {
    SkFont font = font_for(size);
    // The FFI handle is borrowed, while SkFont stores an owning sk_sp. Hold a
    // temporary ref for the font's lifetime without transferring host ownership.
    font.setTypeface(sk_ref_sp(typeface));
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

extern "C" void elisa_skia_canvas_translate(std::size_t handle, float x, float y) {
    if (SkCanvas *target = canvas(handle)) target->translate(x, y);
}

extern "C" void elisa_skia_canvas_rotate(std::size_t handle, float degrees) {
    if (SkCanvas *target = canvas(handle)) target->rotate(degrees);
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

extern "C" void elisa_skia_canvas_fill_round_rect(std::size_t handle, float x, float y, float width,
                                                    float height, float radius, std::uint8_t red,
                                                    std::uint8_t green, std::uint8_t blue,
                                                    std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle)) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        const SkScalar safe_radius = radius > 0.0f ? radius : 0.0f;
        target->drawRRect(SkRRect::MakeRectXY(rect, safe_radius, safe_radius),
                          fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_stroke_round_rect(std::size_t handle, float x, float y, float width,
                                                      float height, float radius, float stroke_width,
                                                      std::uint8_t red,
                                                      std::uint8_t green, std::uint8_t blue,
                                                      std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle); target != nullptr && stroke_width > 0.0f) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        const SkScalar safe_radius = radius > 0.0f ? radius : 0.0f;
        target->drawRRect(SkRRect::MakeRectXY(rect, safe_radius, safe_radius),
                          stroke_paint(red, green, blue, alpha, stroke_width));
    }
}

extern "C" void elisa_skia_canvas_shadow_round_rect(std::size_t handle, float x, float y, float width,
                                                      float height, float radius, float offset_x,
                                                      float offset_y, float blur, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle); alpha != 0) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        const SkScalar safe_radius = radius > 0.0f ? radius : 0.0f;
        // The shadow layer is the only visible effect. A black fill here would
        // paint over the retained control before the hairline is emitted.
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setStyle(SkPaint::kFill_Style);
        paint.setColor(SK_ColorTRANSPARENT);
        paint.setShadowLayer(blur, offset_x, offset_y, color(0, 0, 0, alpha));
        target->drawRRect(SkRRect::MakeRectXY(rect, safe_radius, safe_radius), paint);
    }
}

extern "C" void elisa_skia_canvas_draw_image(std::size_t canvas_handle, std::size_t image_handle,
                                               float x, float y, float width, float height,
                                               std::uint8_t alpha) {
    elisa_skia_canvas_draw_image_sampling(canvas_handle, image_handle, x, y, width, height, alpha, 1);
}

extern "C" void elisa_skia_canvas_draw_image_sampling(std::size_t canvas_handle, std::size_t image_handle,
                                                        float x, float y, float width, float height,
                                                        std::uint8_t alpha, std::int32_t sampling) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && image_handle != 0 && width > 0.0f && height > 0.0f && alpha != 0) {
        SkImage *image = reinterpret_cast<SkImage *>(image_handle);
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setAlphaf(static_cast<float>(alpha) / 255.0f);
        const SkFilterMode filter = sampling == 0 ? SkFilterMode::kNearest : SkFilterMode::kLinear;
        target->drawImageRect(image, SkRect::MakeXYWH(x, y, width, height),
                              SkSamplingOptions(filter, SkMipmapMode::kNone),
                              &paint);
    }
}

extern "C" void elisa_skia_canvas_draw_text_with_font(std::size_t canvas_handle,
                                                        std::size_t font_handle,
                                                        const char *text, std::size_t length,
                                                        float x, float y, float size,
                                                        std::uint8_t red, std::uint8_t green,
                                                        std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && font_handle != 0 && text != nullptr && length > 0) {
        SkFont font = font_for(size, reinterpret_cast<SkTypeface *>(font_handle));
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font,
                               fill_paint(red, green, blue, alpha));
    }
}

extern "C" float elisa_skia_measure_text_width_with_font(std::size_t font_handle,
                                                           const char *text, std::size_t length,
                                                           float size) {
    if (font_handle == 0 || text == nullptr || length == 0) return 0.0f;
    return font_for(size, reinterpret_cast<SkTypeface *>(font_handle))
        .measureText(text, length, SkTextEncoding::kUTF8);
}

extern "C" float elisa_skia_font_ascent_with_font(std::size_t font_handle, float size) {
    if (font_handle == 0) return 0.0f;
    SkFontMetrics metrics;
    font_for(size, reinterpret_cast<SkTypeface *>(font_handle)).getMetrics(&metrics);
    return -metrics.fAscent;
}

extern "C" float elisa_skia_text_line_height_with_font(std::size_t font_handle, float size) {
    if (font_handle == 0) return 0.0f;
    SkFontMetrics metrics;
    font_for(size, reinterpret_cast<SkTypeface *>(font_handle)).getMetrics(&metrics);
    return metrics.fDescent - metrics.fAscent + metrics.fLeading;
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
                                              float stroke_width, std::uint8_t red, std::uint8_t green,
                                              std::uint8_t blue,
                                              std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle); target != nullptr && stroke_width > 0.0f) {
        target->drawLine(x0, y0, x1, y1, stroke_paint(red, green, blue, alpha, stroke_width));
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
