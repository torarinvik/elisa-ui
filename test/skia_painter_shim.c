// Headless recorder for the Elisa/Skia painter contract.
// This is test-only: production hosts provide these symbols from Skia.

#include <stddef.h>
#include <stdint.h>

#include "../include/elisa_skia.h"

static int save_count;
static int restore_count;
static int scale_count;
static int translate_count;
static int rotate_count;
static int clip_count;
static int rounded_clip_count;
static int clear_count;
static int round_rect_count;
static int stroke_round_rect_count;
static int shadow_round_rect_count;
static int gradient_count;
static int last_gradient_horizontal;
static float last_shadow_offset_x;
static float last_shadow_offset_y;
static float last_shadow_blur;
static int image_count;
static int circle_count;
static int stroke_circle_count;
static int triangle_count;
static int line_count;
static int text_count;
static int measure_width_count;
static float last_round_radius;
static float last_clip_radius;
static float last_stroke_width;
static float last_circle_stroke_width;
static float last_line_width;
static float last_text_size;
static float last_image_x;
static float last_image_y;
static float last_image_width;
static float last_image_height;
static int last_image_sampling;
static float last_image_source_x;
static float last_image_source_y;
static float last_image_source_width;
static float last_image_source_height;

void elisa_skia_canvas_save(size_t canvas) { if (canvas != 0) save_count += 1; }
void elisa_skia_canvas_restore(size_t canvas) { if (canvas != 0) restore_count += 1; }
void elisa_skia_canvas_scale(size_t canvas, float x, float y) {
    (void)x; (void)y;
    if (canvas != 0) scale_count += 1;
}
void elisa_skia_canvas_translate(size_t canvas, float x, float y) {
    (void)x; (void)y;
    if (canvas != 0) translate_count += 1;
}
void elisa_skia_canvas_rotate(size_t canvas, float degrees) {
    (void)degrees;
    if (canvas != 0) rotate_count += 1;
}
void elisa_skia_canvas_clip_rect(size_t canvas, float x, float y, float width, float height) {
    (void)x; (void)y; (void)width; (void)height;
    if (canvas != 0) clip_count += 1;
}
void elisa_skia_canvas_clip_round_rect(size_t canvas, float x, float y, float width, float height, float radius) {
    (void)x; (void)y; (void)width; (void)height;
    if (canvas != 0) { rounded_clip_count += 1; last_clip_radius = radius; }
}
void elisa_skia_canvas_clear(size_t canvas, uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) clear_count += 1;
}
void elisa_skia_canvas_fill_round_rect(size_t canvas, float x, float y, float width,
                                       float height, float radius, uint8_t red,
                                       uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { round_rect_count += 1; last_round_radius = radius; }
}
void elisa_skia_canvas_stroke_round_rect(size_t canvas, float x, float y, float width,
                                         float height, float radius, float stroke_width, uint8_t red,
                                         uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { stroke_round_rect_count += 1; last_stroke_width = stroke_width; }
}
void elisa_skia_canvas_shadow_round_rect(size_t canvas, float x, float y, float width,
                                         float height, float radius, float offset_x,
                                         float offset_y, float blur, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height; (void)radius; (void)alpha;
    if (canvas != 0) {
        shadow_round_rect_count += 1;
        last_shadow_offset_x = offset_x;
        last_shadow_offset_y = offset_y;
        last_shadow_blur = blur;
    }
}
void elisa_skia_canvas_fill_linear_gradient(size_t canvas, float x, float y, float width, float height,
                                            uint8_t start_red, uint8_t start_green, uint8_t start_blue,
                                            uint8_t start_alpha, uint8_t end_red, uint8_t end_green,
                                            uint8_t end_blue, uint8_t end_alpha, int32_t horizontal) {
    (void)x; (void)y; (void)width; (void)height; (void)start_red; (void)start_green; (void)start_blue;
    (void)start_alpha; (void)end_red; (void)end_green; (void)end_blue; (void)end_alpha;
    if (canvas != 0) { gradient_count += 1; last_gradient_horizontal = horizontal; }
}
void elisa_skia_canvas_draw_image(size_t canvas, size_t image, float x, float y,
                                  float width, float height, uint8_t alpha) {
    (void)image; (void)alpha;
    if (canvas != 0) {
        image_count += 1; last_image_sampling = 1;
        last_image_x = x; last_image_y = y; last_image_width = width; last_image_height = height;
    }
}
void elisa_skia_canvas_draw_image_sampling(size_t canvas, size_t image, float x, float y,
                                           float width, float height, uint8_t alpha, int sampling) {
    (void)image; (void)alpha;
    if (canvas != 0) {
        image_count += 1; last_image_sampling = sampling;
        last_image_x = x; last_image_y = y; last_image_width = width; last_image_height = height;
    }
}
void elisa_skia_canvas_draw_image_source_sampling(size_t canvas, size_t image,
                                                  float source_x, float source_y,
                                                  float source_width, float source_height,
                                                  float x, float y, float width, float height,
                                                  uint8_t alpha, int sampling) {
    (void)image; (void)alpha;
    if (canvas != 0) {
        image_count += 1; last_image_sampling = sampling;
        last_image_source_x = source_x; last_image_source_y = source_y;
        last_image_source_width = source_width; last_image_source_height = source_height;
        last_image_x = x; last_image_y = y; last_image_width = width; last_image_height = height;
    }
}
void elisa_skia_canvas_draw_text_with_font(size_t canvas, size_t font, const char *text,
                                           size_t length, float x, float y, float size,
                                           uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)font; (void)text; (void)length; (void)x; (void)y; (void)size;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { text_count += 1; last_text_size = size; }
}
void elisa_skia_canvas_fill_circle(size_t canvas, float x, float y, float radius,
                                   uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) circle_count += 1;
}
void elisa_skia_canvas_stroke_circle(size_t canvas, float x, float y, float radius, float stroke_width,
                                     uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { stroke_circle_count += 1; last_circle_stroke_width = stroke_width; }
}
void elisa_skia_canvas_fill_triangle(size_t canvas, float ax, float ay, float bx, float by,
                                     float cx, float cy, uint8_t red, uint8_t green,
                                     uint8_t blue, uint8_t alpha) {
    (void)ax; (void)ay; (void)bx; (void)by; (void)cx; (void)cy;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) triangle_count += 1;
}
void elisa_skia_canvas_fill_line(size_t canvas, float x0, float y0, float x1, float y1,
                                 float stroke_width, uint8_t red, uint8_t green, uint8_t blue,
                                 uint8_t alpha) {
    (void)x0; (void)y0; (void)x1; (void)y1;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { line_count += 1; last_line_width = stroke_width; }
}
void elisa_skia_canvas_draw_text(size_t canvas, const char *text, size_t length,
                                 float x, float y, float size, uint8_t red,
                                 uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)text; (void)length; (void)x; (void)y; (void)size;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { text_count += 1; last_text_size = size; }
}

float elisa_skia_measure_text_width(const char *text, size_t length, float size) {
    measure_width_count += 1;
    return text == NULL ? 0.0f : (float)length * size * 0.5f;
}
float elisa_skia_font_ascent(float size) { return size * 0.8f; }
float elisa_skia_text_line_height(float size) { return size * 1.2f; }
float elisa_skia_measure_text_width_with_font(size_t font, const char *text, size_t length, float size) {
    measure_width_count += 1;
    return font == 0 || text == NULL ? 0.0f : (float)length * size * 0.6f;
}
float elisa_skia_font_ascent_with_font(size_t font, float size) { return font == 0 ? 0.0f : size * 0.85f; }
float elisa_skia_text_line_height_with_font(size_t font, float size) { return font == 0 ? 0.0f : size * 1.25f; }

void skia_test_reset(void) {
    save_count = 0; restore_count = 0; scale_count = 0; translate_count = 0; rotate_count = 0; clip_count = 0; rounded_clip_count = 0;
    clear_count = 0; round_rect_count = 0; stroke_round_rect_count = 0; shadow_round_rect_count = 0; gradient_count = 0; image_count = 0; circle_count = 0; stroke_circle_count = 0; triangle_count = 0;
    last_shadow_offset_x = 0.0f; last_shadow_offset_y = 0.0f; last_shadow_blur = 0.0f;
    line_count = 0; text_count = 0; measure_width_count = 0; last_round_radius = 0.0f; last_clip_radius = 0.0f; last_stroke_width = 0.0f; last_circle_stroke_width = 0.0f; last_line_width = 0.0f; last_text_size = 0.0f; last_image_x = 0.0f; last_image_y = 0.0f; last_image_width = 0.0f; last_image_height = 0.0f; last_image_source_x = 0.0f; last_image_source_y = 0.0f; last_image_source_width = 0.0f; last_image_source_height = 0.0f; last_image_sampling = 1; last_gradient_horizontal = 0;
}
int skia_test_save_count(void) { return save_count; }
int skia_test_restore_count(void) { return restore_count; }
int skia_test_scale_count(void) { return scale_count; }
int skia_test_translate_count(void) { return translate_count; }
int skia_test_rotate_count(void) { return rotate_count; }
int skia_test_clip_count(void) { return clip_count; }
int skia_test_rounded_clip_count(void) { return rounded_clip_count; }
int skia_test_clear_count(void) { return clear_count; }
int skia_test_round_rect_count(void) { return round_rect_count; }
int skia_test_stroke_round_rect_count(void) { return stroke_round_rect_count; }
int skia_test_shadow_round_rect_count(void) { return shadow_round_rect_count; }
int skia_test_gradient_count(void) { return gradient_count; }
int skia_test_last_gradient_horizontal(void) { return last_gradient_horizontal; }
float skia_test_last_shadow_offset_x(void) { return last_shadow_offset_x; }
float skia_test_last_shadow_offset_y(void) { return last_shadow_offset_y; }
float skia_test_last_shadow_blur(void) { return last_shadow_blur; }
float skia_test_last_stroke_width(void) { return last_stroke_width; }
float skia_test_last_circle_stroke_width(void) { return last_circle_stroke_width; }
float skia_test_last_line_width(void) { return last_line_width; }
int skia_test_image_count(void) { return image_count; }
int skia_test_circle_count(void) { return circle_count; }
int skia_test_stroke_circle_count(void) { return stroke_circle_count; }
int skia_test_triangle_count(void) { return triangle_count; }
int skia_test_line_count(void) { return line_count; }
int skia_test_text_count(void) { return text_count; }
int skia_test_measure_width_count(void) { return measure_width_count; }
float skia_test_last_text_size(void) { return last_text_size; }
float skia_test_last_round_radius(void) { return last_round_radius; }
float skia_test_last_clip_radius(void) { return last_clip_radius; }
int skia_test_last_image_sampling(void) { return last_image_sampling; }
float skia_test_last_image_x(void) { return last_image_x; }
float skia_test_last_image_y(void) { return last_image_y; }
float skia_test_last_image_width(void) { return last_image_width; }
float skia_test_last_image_height(void) { return last_image_height; }
float skia_test_last_image_source_x(void) { return last_image_source_x; }
float skia_test_last_image_source_y(void) { return last_image_source_y; }
float skia_test_last_image_source_width(void) { return last_image_source_width; }
float skia_test_last_image_source_height(void) { return last_image_source_height; }
