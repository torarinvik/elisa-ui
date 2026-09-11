// Narrow C ABI for the Elisa Skia painter: the CANVAS half.
//
// The custom renderer never exposes SkCanvas, SkPaint, or SkFont through the
// Elisa ABI. A host owns the surface and passes one borrowed SkCanvas* for the
// duration of a frame; every primitive below validates that opaque handle
// before messaging Skia. Build this file only in a target that provides Skia.
//
// The text half is skia_text_shim.cpp; what they share is skia_shim_common.h.

#include "skia_shim_common.h"

using namespace elisa_skia_shim;

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
        const SkRRect rounded = SkRRect::MakeRectXY(rect, radius, radius);
        // A blur mask filter on the offset shape, NOT a drop-shadow image
        // filter. The two produce the same picture -- the shape's alpha,
        // blurred by the same sigma, moved by the offset, painted in the
        // shadow colour -- but they cost wildly different amounts on a CPU
        // raster surface. An image filter has to open a layer, rasterize the
        // shape into it, run a general separable blur over the whole layer and
        // composite the result back. A blur mask filter on a round rect is
        // recognized by the rasterizer, which computes one edge profile and
        // stretches it into a nine-patch: no layer, no per-pixel blur. A
        // profile of the Android storefront had over 70% of every frame inside
        // the general blur; almost all of it was these shadows.
        SkPaint paint = fill_paint(red, green, blue, alpha);
        if (blur > 0.0f) {
            paint.setMaskFilter(SkMaskFilter::MakeBlur(kNormal_SkBlurStyle, blur));
        }
        // AN OUTER SHADOW IS OUTSIDE. The part of it that falls under the
        // surface is invisible while the surface is opaque and is a stain the
        // moment it is not: a translucent panel would be darkened by its own
        // shadow, which is why CSS clips an outer box-shadow out of the border
        // box rather than letting it show through. The clip costs nothing in
        // the opaque case, where those pixels were being covered anyway.
        target->save();
        target->clipRRect(rounded, SkClipOp::kDifference, true);
        target->drawRRect(rounded.makeOffset(offset_x, offset_y), paint);
        target->restore();
    }
}


// GLASS: blur what is already on the canvas, inside a rounded rectangle.
//

// This is the one effect in the framework that cannot be composed from the

// primitives above, because it is a function of the pixels UNDER the surface

// rather than of the surface. A layer opened with a backdrop filter is

// initialized with the filtered content beneath it; restoring it immediately

// composites that blurred copy back through the clip, which leaves the region

// blurred and nothing else drawn. The translucent fill the framework paints

// next is what turns it from a smear into glass.

extern "C" void elisa_skia_canvas_blur_behind_round_rect(std::size_t handle, float x, float y,
                                                           float width, float height, float radius,
                                                           float sigma) {
    SkCanvas *target = canvas(handle);
    if (target == nullptr || !valid_rect(x, y, width, height) ||
        !bounded_nonnegative_extent(radius) || !bounded_nonnegative_extent(sigma) || sigma <= 0.0f) {
        return;
    }
    const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
    sk_sp<SkImageFilter> blur = SkImageFilters::Blur(sigma, sigma, nullptr);
    if (blur == nullptr) {
        return;
    }
    target->save();
    target->clipRRect(SkRRect::MakeRectXY(rect, radius, radius), true);
    target->saveLayer(SkCanvas::SaveLayerRec(&rect, nullptr, blur.get(), 0));
    target->restore();
    target->restore();
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


// AN INNER SHADOW IS INSIDE. The shape's own outside, blurred and shifted,
// clipped to the shape: only the blur that bleeds back across the edge
// survives, which is a shadow cast by the lip onto the face. This is what
// makes glass read as a slab with thickness rather than a tint with an
// outline -- a bright bleed at the top edge, a dark one at the bottom.
extern "C" void elisa_skia_canvas_inner_shadow_round_rect(std::size_t handle, float x, float y, float width,
                                                          float height, float radius, float offset_y,
                                                          float blur, std::uint8_t red, std::uint8_t green,
                                                          std::uint8_t blue, std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius) &&
        bounded_coordinate(offset_y) && bounded_extent(blur) && alpha != 0) {
        const SkRect rect = SkRect::MakeXYWH(x, y, width, height);
        const SkRRect rounded = SkRRect::MakeRectXY(rect, radius, radius);
        // Say that as "the shadow colour everywhere inside the shape, with the
        // blurred shape taken back out of it" rather than as "the blurred
        // complement of the shape". The two are the same picture -- one minus
        // the blurred shape, either way -- but the second asks Skia to blur a
        // rectangle with a rounded hole in it, which is a mask it has to blur
        // pixel by pixel, and the first asks it to blur a round rect, which it
        // builds from a single edge profile and stretches. Subtracting needs a
        // layer, because no blend mode reads "one minus the source" straight
        // onto the canvas; the layer is the price of the fast shape.
        SkPaint cut = fill_paint(0, 0, 0, 255);
        cut.setBlendMode(SkBlendMode::kDstOut);
        if (blur > 0.0f) {
            cut.setMaskFilter(SkMaskFilter::MakeBlur(kNormal_SkBlurStyle, blur));
        }
        target->save();
        target->clipRRect(rounded, SkClipOp::kIntersect, true);
        target->saveLayer(&rect, nullptr);
        target->drawColor(color(red, green, blue, alpha));
        target->drawRRect(rounded.makeOffset(0.0f, offset_y), cut);
        target->restore();
        target->restore();
    }
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


extern "C" void elisa_skia_canvas_fill_round_rect_gradient3(std::size_t handle, float x, float y,
                                                             float width, float height, float radius,
                                                             std::uint32_t start, std::uint32_t mid,
                                                             float mid_at, std::uint32_t end,
                                                             std::int32_t horizontal) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && valid_rect(x, y, width, height) && bounded_nonnegative_extent(radius) &&
        finite(mid_at) && mid_at > 0.0f && mid_at < 1.0f) {
        SkPaint paint;
        paint.setAntiAlias(true);
        paint.setShader(three_stop_shader(x, y, width, height, start, mid, mid_at, end, horizontal));
        target->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, width, height), radius, radius), paint);
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


// A picture repeated across a rounded box at its own size: an image shader
// with repeat tiling, filled into the shape. Grain over a ramp is the case
// that wants it -- a 64-pixel noise tile over a full page, at a few percent.
extern "C" void elisa_skia_canvas_draw_image_tiled(std::size_t canvas_handle, std::size_t image_handle,
                                                   float x, float y, float width, float height,
                                                   float radius, std::uint8_t alpha) {
    SkCanvas *target = canvas(canvas_handle);
    SkImage *image = reinterpret_cast<SkImage *>(image_handle);
    if (target == nullptr || image == nullptr || !valid_rect(x, y, width, height) ||
        !bounded_nonnegative_extent(radius) || alpha == 0) return;
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setAlpha(alpha);
    // Anchor the tile grid at the box's origin so the pattern does not swim
    // when the box moves.
    const SkMatrix at = SkMatrix::Translate(x, y);
    paint.setShader(image->makeShader(SkTileMode::kRepeat, SkTileMode::kRepeat,
                                      SkSamplingOptions(SkFilterMode::kNearest), &at));
    target->drawRRect(SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, width, height), radius, radius), paint);
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


// MEASURE THE FACE YOU WILL DRAW WITH. A stroke does not change an advance, so

// while weight was synthetic this could ignore its argument -- and did. A

// designed bold has its own advances, so the moment a host lends one this has

// to select it too, or every weighted label is laid out to the width of its

// regular self and clipped.

// Lend the renderer a bold face, or pass zero to take it back. Borrowed like

// every other font handle: the host owns it and must outlive the frames that

// use it.

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


// The cap is an appearance decision and arrives as a value; this bridge must

// not pick one. A butt cap is what makes a thick diagonal look chipped, which

// is visible the moment a line is wider than a hairline.

extern "C" void elisa_skia_canvas_fill_line(std::size_t handle, float x0, float y0, float x1, float y1,
                                              float stroke_width, std::int32_t round_cap,
                                              std::uint8_t red, std::uint8_t green,
                                              std::uint8_t blue,
                                              std::uint8_t alpha) {
    if (SkCanvas *target = canvas(handle);
        target != nullptr && bounded_coordinate(x0) && bounded_coordinate(y0) && bounded_coordinate(x1) &&
        bounded_coordinate(y1) && bounded_extent(stroke_width)) {
        SkPaint paint = stroke_paint(red, green, blue, alpha, stroke_width);
        paint.setStrokeCap(round_cap != 0 ? SkPaint::kRound_Cap : SkPaint::kButt_Cap);
        target->drawLine(x0, y0, x1, y1, paint);
    }
}
