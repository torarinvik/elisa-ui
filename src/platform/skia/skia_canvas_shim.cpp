// Narrow C ABI for the Elisa Skia painter.
//
// The custom renderer never exposes SkCanvas, SkPaint, or SkFont through the
// Elisa ABI. A host owns the surface and passes one borrowed SkCanvas* for the
// duration of a frame; every primitive below validates that opaque handle
// before messaging Skia. Build this file only in a target that provides Skia.

#include <cstddef>
#include <cstdint>
#include <cmath>

#include "../../../include/elisa_skia.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMetrics.h"
#include "include/core/SkImage.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkRect.h"
#include "include/core/SkRRect.h"
#include "include/core/SkSamplingOptions.h"
#include "include/core/SkShader.h"
#include "include/core/SkTypeface.h"
#include "include/effects/SkImageFilters.h"
#include "include/effects/SkGradient.h"

namespace {

SkCanvas *canvas(std::size_t handle) {
    return reinterpret_cast<SkCanvas *>(handle);
}

bool finite(float value) {
    return std::isfinite(value);
}

constexpr float max_geometry_extent = 16777216.0f;

bool bounded_coordinate(float value) {
    return finite(value) && value >= -max_geometry_extent && value <= max_geometry_extent;
}

bool bounded_extent(float value) {
    return finite(value) && value > 0.0f && value <= max_geometry_extent;
}

bool bounded_nonnegative_extent(float value) {
    return finite(value) && value >= 0.0f && value <= max_geometry_extent;
}

bool bounded_far_edge(float origin, float extent) {
    const float edge = origin + extent;
    return finite(edge) && edge <= max_geometry_extent;
}

bool valid_rect(float x, float y, float width, float height) {
    return bounded_coordinate(x) && bounded_coordinate(y) && bounded_extent(width) && bounded_extent(height) &&
        bounded_far_edge(x, width) && bounded_far_edge(y, height);
}

// Retained clips may intentionally be empty after Elisa intersects nested
// viewports. Keep that semantic distinction at the primitive boundary: a
// zero-sized clip is a valid Skia operation that suppresses subsequent draws,
// while negative or non-finite geometry remains malformed and is rejected.
bool valid_clip_rect(float x, float y, float width, float height) {
    return bounded_coordinate(x) && bounded_coordinate(y) && bounded_nonnegative_extent(width) &&
        bounded_nonnegative_extent(height) && bounded_far_edge(x, width) && bounded_far_edge(y, height);
}

bool valid_source_rect(float x, float y, float width, float height) {
    return x >= 0.0f && y >= 0.0f && valid_rect(x, y, width, height);
}

bool valid_circle(float x, float y, float radius) {
    return bounded_coordinate(x) && bounded_coordinate(y) && bounded_extent(radius) &&
        finite(x - radius) && finite(x + radius) && finite(y - radius) && finite(y + radius) &&
        x - radius >= -max_geometry_extent && x + radius <= max_geometry_extent &&
        y - radius >= -max_geometry_extent && y + radius <= max_geometry_extent;
}

bool valid_stroked_circle(float x, float y, float radius, float stroke_width) {
    return valid_circle(x, y, radius) && bounded_extent(stroke_width) &&
        valid_circle(x, y, radius + stroke_width * 0.5f);
}

bool valid_scale(float x, float y) {
    return bounded_extent(x) && bounded_extent(y);
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

// Text quality is chosen by Elisa and applied here. Both knobs change how
// glyphs land on the pixel grid rather than what is drawn, so they are one
// process-wide setting instead of an argument on every draw call.
int elisa_skia_text_subpixel = 0;
int elisa_skia_text_hinting = 0;

SkFontHinting hinting_for(int hinting) {
    switch (hinting) {
        case 1: return SkFontHinting::kSlight;
        case 2: return SkFontHinting::kNormal;
        case 3: return SkFontHinting::kFull;
        default: return SkFontHinting::kNone;
    }
}

SkFont font_for(float size) {
    SkFont font;
    font.setSize(size);
    font.setEdging(SkFont::Edging::kAntiAlias);
    font.setSubpixel(elisa_skia_text_subpixel != 0);
    font.setHinting(hinting_for(elisa_skia_text_hinting));
    return font;
}

// A two-stop gradient down (or across) a box. The STOP POLICY stays in Elisa --
// two evenly spaced stops, no positions supplied -- so this is only the shader
// construction the C++ side has to own.
sk_sp<SkShader> two_stop_shader(float x, float y, float width, float height,
                                std::uint8_t start_red, std::uint8_t start_green,
                                std::uint8_t start_blue, std::uint8_t start_alpha,
                                std::uint8_t end_red, std::uint8_t end_green,
                                std::uint8_t end_blue, std::uint8_t end_alpha,
                                std::int32_t horizontal) {
    const SkPoint points[] = {
        {x, y},
        {horizontal != 0 ? x + width : x, horizontal != 0 ? y : y + height},
    };
    const SkColor4f colors[] = {
        SkColor4f::FromColor(color(start_red, start_green, start_blue, start_alpha)),
        SkColor4f::FromColor(color(end_red, end_green, end_blue, end_alpha)),
    };
    const SkGradient gradient({SkSpan(colors), SkTileMode::kClamp}, {});
    return SkShaders::LinearGradient(points, gradient);
}

SkFont font_for(float size, SkTypeface *typeface) {
    SkFont font = font_for(size);
    // The FFI handle is borrowed, while SkFont stores an owning sk_sp. Hold a
    // temporary ref for the font's lifetime without transferring host ownership.
    font.setTypeface(sk_ref_sp(typeface));
    return font;
}

// Weight, from the ONE typeface a host lends the renderer.
//
// A host hands over a single borrowed SkTypeface for the frame, so there is no
// bold face to select; `setEmbolden` dilates the outline of the face that is
// there. Measured against this pin: it does NOT change advances -- the same
// string measures 297.1406 with and without it -- so a weighted run occupies
// exactly the box the layout pass measured for it, and text weight costs the
// framework no second measurement path and no risk of clipped labels.
SkFont font_for(float size, SkTypeface *typeface, int weighted) {
    SkFont font = typeface != nullptr ? font_for(size, typeface) : font_for(size);
    font.setEmbolden(weighted != 0);
    return font;
}

}

extern "C" void elisa_skia_set_text_quality(int subpixel, int hinting) {
    elisa_skia_text_subpixel = subpixel != 0 ? 1 : 0;
    elisa_skia_text_hinting = hinting;
}

extern "C" void elisa_skia_canvas_save(std::size_t handle) {
    if (SkCanvas *target = canvas(handle)) target->save();
}

extern "C" void elisa_skia_canvas_restore(std::size_t handle) {
    if (SkCanvas *target = canvas(handle)) target->restore();
}

extern "C" void elisa_skia_canvas_scale(std::size_t handle, float x, float y) {
    if (SkCanvas *target = canvas(handle); target != nullptr && valid_scale(x, y)) {
        target->scale(x, y);
    }
}

extern "C" void elisa_skia_canvas_translate(std::size_t handle, float x, float y) {
    if (SkCanvas *target = canvas(handle); target != nullptr && bounded_coordinate(x) && bounded_coordinate(y)) {
        target->translate(x, y);
    }
}

extern "C" void elisa_skia_canvas_rotate(std::size_t handle, float degrees) {
    if (SkCanvas *target = canvas(handle); target != nullptr && bounded_coordinate(degrees)) {
        target->rotate(degrees);
    }
}

extern "C" void elisa_skia_canvas_clip_rect(std::size_t handle, float x, float y, float width, float height) {
    if (SkCanvas *target = canvas(handle); target != nullptr && valid_clip_rect(x, y, width, height)) {
        target->clipRect(SkRect::MakeXYWH(x, y, width, height), SkClipOp::kIntersect, true);
    }
}

extern "C" void elisa_skia_canvas_clip_round_rect(std::size_t handle, float x, float y, float width,
                                                     float height, float radius) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_clip_rect(x, y, width, height) && bounded_nonnegative_extent(radius)) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        target->clipRRect(SkRRect::MakeRectXY(rect, radius, radius), SkClipOp::kIntersect, true);
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
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius)) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        target->drawRRect(SkRRect::MakeRectXY(rect, radius, radius),
                          fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_stroke_round_rect(std::size_t handle, float x, float y, float width,
                                                      float height, float radius, float stroke_width,
                                                      std::uint8_t red,
                                                      std::uint8_t green, std::uint8_t blue,
                                                      std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius) &&
        bounded_extent(stroke_width)) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        target->drawRRect(SkRRect::MakeRectXY(rect, radius, radius),
                          stroke_paint(red, green, blue, alpha, stroke_width));
    }
}

extern "C" void elisa_skia_canvas_shadow_round_rect_color(std::size_t handle, float x, float y, float width,
                                                            float height, float radius, float offset_x,
                                                            float offset_y, float blur, std::uint8_t red,
                                                            std::uint8_t green, std::uint8_t blue,
                                                            std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius) &&
        bounded_coordinate(offset_x) && bounded_coordinate(offset_y) && bounded_nonnegative_extent(blur) &&
        alpha != 0) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        // DropShadowOnly keeps the source silhouette out of the result while
        // still using its alpha as the shadow mask. This is the replacement
        // for the removed SkPaint::setShadowLayer API in current Skia.
        SkPaint paint = fill_paint(0, 0, 0, 255);
        paint.setImageFilter(SkImageFilters::DropShadowOnly(
            offset_x, offset_y, blur, blur, color(red, green, blue, alpha), nullptr));
        target->drawRRect(SkRRect::MakeRectXY(rect, radius, radius), paint);
    }
}

// Compatibility entry point for hosts compiled against the original ABI. Elisa
// uses the color-aware primitive above, so black is no longer a native visual
// default on the framework path.
extern "C" void elisa_skia_canvas_shadow_round_rect(std::size_t handle, float x, float y, float width,
                                                      float height, float radius, float offset_x,
                                                      float offset_y, float blur, std::uint8_t alpha) {
    elisa_skia_canvas_shadow_round_rect_color(handle, x, y, width, height, radius,
                                              offset_x, offset_y, blur, 0, 0, 0, alpha);
}

extern "C" void elisa_skia_canvas_fill_linear_gradient(std::size_t handle, float x, float y,
                                                         float width, float height,
                                                         std::uint8_t start_red,
                                                         std::uint8_t start_green,
                                                         std::uint8_t start_blue,
                                                         std::uint8_t start_alpha,
                                                         std::uint8_t end_red,
                                                         std::uint8_t end_green,
                                                         std::uint8_t end_blue,
                                                         std::uint8_t end_alpha,
                                                         std::int32_t horizontal) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && (start_alpha != 0 || end_alpha != 0)) {
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setShader(two_stop_shader(x, y, width, height, start_red, start_green, start_blue,
                                        start_alpha, end_red, end_green, end_blue, end_alpha,
                                        horizontal));
        target->drawRect(SkRect::MakeXYWH(x, y, width, height), paint);
    }
}

extern "C" void elisa_skia_canvas_fill_round_rect_gradient(std::size_t handle, float x, float y,
                                                            float width, float height, float radius,
                                                            std::uint8_t start_red,
                                                            std::uint8_t start_green,
                                                            std::uint8_t start_blue,
                                                            std::uint8_t start_alpha,
                                                            std::uint8_t end_red,
                                                            std::uint8_t end_green,
                                                            std::uint8_t end_blue,
                                                            std::uint8_t end_alpha,
                                                            std::int32_t horizontal) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius) &&
        (start_alpha != 0 || end_alpha != 0)) {
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setShader(two_stop_shader(x, y, width, height, start_red, start_green, start_blue,
                                        start_alpha, end_red, end_green, end_blue, end_alpha,
                                        horizontal));
        target->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, width, height), radius, radius),
                          paint);
    }
}

extern "C" void elisa_skia_canvas_stroke_round_rect_gradient(std::size_t handle, float x, float y,
                                                               float width, float height, float radius,
                                                               float stroke_width,
                                                               std::uint8_t start_red,
                                                               std::uint8_t start_green,
                                                               std::uint8_t start_blue,
                                                               std::uint8_t start_alpha,
                                                               std::uint8_t end_red,
                                                               std::uint8_t end_green,
                                                               std::uint8_t end_blue,
                                                               std::uint8_t end_alpha,
                                                               std::int32_t horizontal) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius) &&
        bounded_extent(stroke_width) && (start_alpha != 0 || end_alpha != 0)) {
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setStyle(SkPaint::kStroke_Style);
        paint.setStrokeWidth(stroke_width);
        paint.setShader(two_stop_shader(x, y, width, height, start_red, start_green, start_blue,
                                        start_alpha, end_red, end_green, end_blue, end_alpha,
                                        horizontal));
        target->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, width, height), radius, radius),
                          paint);
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
        target != nullptr && image_handle != 0 && valid_rect(x, y, width, height) && alpha != 0) {
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

extern "C" void elisa_skia_canvas_draw_image_source_sampling(
    std::size_t canvas_handle, std::size_t image_handle,
    float source_x, float source_y, float source_width, float source_height,
    float x, float y, float width, float height,
    std::uint8_t alpha, std::int32_t sampling) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && image_handle != 0 &&
        valid_source_rect(source_x, source_y, source_width, source_height) &&
        valid_rect(x, y, width, height) && alpha != 0) {
        SkImage *image = reinterpret_cast<SkImage *>(image_handle);
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setAlphaf(static_cast<float>(alpha) / 255.0f);
        const SkFilterMode filter = sampling == 0 ? SkFilterMode::kNearest : SkFilterMode::kLinear;
        // Strict: a sub-rect blit must not sample texels outside the source
        // rectangle Elisa asked for, which is what would let a neighbouring
        // sprite in an atlas bleed into this one along its edges.
        target->drawImageRect(image,
                              SkRect::MakeXYWH(source_x, source_y, source_width, source_height),
                              SkRect::MakeXYWH(x, y, width, height),
                              SkSamplingOptions(filter, SkMipmapMode::kNone), &paint,
                              SkCanvas::kStrict_SrcRectConstraint);
    }
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
                                                       std::int32_t weighted,
                                                       std::uint8_t red, std::uint8_t green,
                                                       std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(canvas_handle);
        target != nullptr && text != nullptr && length > 0 && bounded_coordinate(x) &&
        bounded_coordinate(y) && bounded_extent(size)) {
        const SkFont font = font_for(size, reinterpret_cast<SkTypeface *>(font_handle), weighted);
        target->drawSimpleText(text, length, SkTextEncoding::kUTF8, x, y, font,
                               fill_paint(red, green, blue, alpha));
    }
}

extern "C" float elisa_skia_measure_text_width_weighted(std::size_t font_handle,
                                                          const char *text, std::size_t length,
                                                          float size, std::int32_t weighted) {
    if (text == nullptr || length == 0 || !bounded_extent(size)) return 0.0f;
    const float measured = font_for(size, reinterpret_cast<SkTypeface *>(font_handle), weighted)
        .measureText(text, length, SkTextEncoding::kUTF8);
    return finite(measured) && measured >= 0.0f ? measured : 0.0f;
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

extern "C" void elisa_skia_canvas_fill_circle(std::size_t handle, float x, float y, float radius,
                                                std::uint8_t red, std::uint8_t green, std::uint8_t blue,
                                                std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_circle(x, y, radius)) {
        target->drawCircle(x, y, radius, fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_stroke_circle(std::size_t handle, float x, float y, float radius,
                                                  float stroke_width, std::uint8_t red,
                                                  std::uint8_t green, std::uint8_t blue,
                                                  std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_stroked_circle(x, y, radius, stroke_width)) {
        target->drawCircle(x, y, radius, stroke_paint(red, green, blue, alpha, stroke_width));
    }
}

extern "C" void elisa_skia_canvas_fill_triangle(std::size_t handle, float ax, float ay, float bx, float by,
                                                 float cx, float cy, std::uint8_t red, std::uint8_t green,
                                                 std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && bounded_coordinate(ax) && bounded_coordinate(ay) && bounded_coordinate(bx) &&
        bounded_coordinate(by) && bounded_coordinate(cx) && bounded_coordinate(cy)) {
        SkPathBuilder path;
        path.moveTo(ax, ay).lineTo(bx, by).lineTo(cx, cy).close();
        target->drawPath(path.detach(), fill_paint(red, green, blue, alpha));
    }
}

extern "C" void elisa_skia_canvas_fill_line(std::size_t handle, float x0, float y0, float x1, float y1,
                                              float stroke_width, std::uint8_t red, std::uint8_t green,
                                              std::uint8_t blue,
                                              std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && bounded_coordinate(x0) && bounded_coordinate(y0) && bounded_coordinate(x1) &&
        bounded_coordinate(y1) && bounded_extent(stroke_width)) {
        target->drawLine(x0, y0, x1, y1, stroke_paint(red, green, blue, alpha, stroke_width));
    }
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
