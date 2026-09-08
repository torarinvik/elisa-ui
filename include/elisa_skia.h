/* elisa-ui: the narrow Skia custom-rendering ABI.
 *
 * A host owns every SkCanvas, SkImage and SkTypeface object. Canvas and direct
 * image/font calls borrow handles for the call (or attached-canvas lifetime).
 * Generation binding APIs store only opaque values until explicit unbind/clear
 * or surface loss, so the host must keep those native objects alive until then.
 * Lifecycle, geometry, text policy and resource generations remain in Elisa's
 * UiSkia modules.
 */
#ifndef ELISA_SKIA_H
#define ELISA_SKIA_H

#include <stddef.h>
#include <stdint.h>

/* Packed as 0xMMmmpp (major, minor, patch). Hosts should check this before
 * submitting an opaque canvas or renderer object to the Skia boundary. */
#define ELISA_SKIA_ABI_VERSION_MAJOR 0u
#define ELISA_SKIA_ABI_VERSION_MINOR 3u
#define ELISA_SKIA_ABI_VERSION_PATCH 0u
#define ELISA_SKIA_ABI_VERSION \
    ((ELISA_SKIA_ABI_VERSION_MAJOR << 16) | \
     (ELISA_SKIA_ABI_VERSION_MINOR << 8) | ELISA_SKIA_ABI_VERSION_PATCH)

#ifdef __cplusplus
extern "C" {
#endif

uint32_t elisa_skia_abi_version(void);
/* One-shot replay boundaries. Elisa attaches, renders, and detaches the
 * borrowed canvas before returning. */
void elisa_skia_render_frame(size_t canvas);
int32_t elisa_skia_render_frame_status(size_t canvas);
/* Uses one borrowed SkTypeface for text commands in this replay only. */
int32_t elisa_skia_render_frame_with_font_status(size_t canvas, size_t font);
void elisa_skia_render_frame_scaled(size_t canvas, float scale);
int32_t elisa_skia_render_frame_scaled_status(size_t canvas, float scale);

void elisa_skia_canvas_save(size_t canvas);
void elisa_skia_canvas_restore(size_t canvas);
void elisa_skia_canvas_scale(size_t canvas, float x, float y);
void elisa_skia_canvas_translate(size_t canvas, float x, float y);
void elisa_skia_canvas_rotate(size_t canvas, float degrees);
void elisa_skia_canvas_clip_rect(size_t canvas, float x, float y, float width, float height);
void elisa_skia_canvas_clip_round_rect(size_t canvas, float x, float y, float width, float height,
                                       float radius);
void elisa_skia_canvas_clear(size_t canvas, uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_fill_round_rect(size_t canvas, float x, float y, float width, float height,
                                       float radius, uint8_t red, uint8_t green, uint8_t blue,
                                       uint8_t alpha);
void elisa_skia_canvas_stroke_round_rect(size_t canvas, float x, float y, float width, float height,
                                         float radius, float stroke_width, uint8_t red,
                                         uint8_t green, uint8_t blue,
                                         uint8_t alpha);
void elisa_skia_canvas_shadow_round_rect(size_t canvas, float x, float y, float width, float height,
                                         float radius, float offset_x, float offset_y, float blur,
                                         uint8_t alpha);
void elisa_skia_canvas_shadow_round_rect_color(size_t canvas, float x, float y, float width, float height,
                                               float radius, float offset_x, float offset_y, float blur,
                                               uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_fill_linear_gradient(size_t canvas, float x, float y, float width, float height,
                                            uint8_t start_red, uint8_t start_green, uint8_t start_blue,
                                            uint8_t start_alpha, uint8_t end_red, uint8_t end_green,
                                            uint8_t end_blue, uint8_t end_alpha, int32_t horizontal);
void elisa_skia_canvas_draw_image(size_t canvas, size_t image, float x, float y, float width,
                                  float height, uint8_t alpha);
void elisa_skia_canvas_draw_image_sampling(size_t canvas, size_t image, float x, float y,
                                           float width, float height, uint8_t alpha,
                                           int32_t sampling);
void elisa_skia_canvas_draw_image_source_sampling(size_t canvas, size_t image,
                                                  float source_x, float source_y,
                                                  float source_width, float source_height,
                                                  float x, float y, float width, float height,
                                                  uint8_t alpha, int32_t sampling);
void elisa_skia_canvas_draw_text(size_t canvas, const char *text, size_t length, float x, float y,
                                 float size, uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_draw_text_with_font(size_t canvas, size_t font, const char *text, size_t length,
                                           float x, float y, float size, uint8_t red, uint8_t green,
                                           uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_fill_circle(size_t canvas, float x, float y, float radius,
                                   uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_stroke_circle(size_t canvas, float x, float y, float radius,
                                     float stroke_width, uint8_t red, uint8_t green,
                                     uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_fill_triangle(size_t canvas, float ax, float ay, float bx, float by,
                                     float cx, float cy, uint8_t red, uint8_t green,
                                     uint8_t blue, uint8_t alpha);
void elisa_skia_canvas_fill_line(size_t canvas, float x0, float y0, float x1, float y1,
                                 float stroke_width, uint8_t red, uint8_t green, uint8_t blue,
                                 uint8_t alpha);

float elisa_skia_measure_text_width(const char *text, size_t length, float size);
float elisa_skia_font_ascent(float size);
float elisa_skia_text_line_height(float size);
float elisa_skia_measure_text_width_with_font(size_t font, const char *text, size_t length,
                                              float size);
float elisa_skia_font_ascent_with_font(size_t font, float size);
float elisa_skia_text_line_height_with_font(size_t font, float size);

#ifdef __cplusplus
}
#endif

#endif /* ELISA_SKIA_H */
