// Headless recorder for the Elisa/Skia painter contract.
// This is test-only: production hosts provide these symbols from Skia.

#include <stddef.h>
#include <stdint.h>

static int save_count;
static int restore_count;
static int scale_count;
static int clip_count;
static int clear_count;
static int rect_count;
static int round_rect_count;
static int stroke_round_rect_count;
static int shadow_round_rect_count;
static int image_count;
static int circle_count;
static int triangle_count;
static int line_count;
static int text_count;
static float last_round_radius;

void elisa_skia_canvas_save(size_t canvas) { if (canvas != 0) save_count += 1; }
void elisa_skia_canvas_restore(size_t canvas) { if (canvas != 0) restore_count += 1; }
void elisa_skia_canvas_scale(size_t canvas, float x, float y) {
    (void)x; (void)y;
    if (canvas != 0) scale_count += 1;
}
void elisa_skia_canvas_clip_rect(size_t canvas, float x, float y, float width, float height) {
    (void)x; (void)y; (void)width; (void)height;
    if (canvas != 0) clip_count += 1;
}
void elisa_skia_canvas_clear(size_t canvas, uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) clear_count += 1;
}
void elisa_skia_canvas_fill_rect(size_t canvas, float x, float y, float width, float height,
                                 uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) rect_count += 1;
}
void elisa_skia_canvas_fill_round_rect(size_t canvas, float x, float y, float width,
                                       float height, float radius, uint8_t red,
                                       uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) { round_rect_count += 1; last_round_radius = radius; }
}
void elisa_skia_canvas_stroke_round_rect(size_t canvas, float x, float y, float width,
                                         float height, float radius, uint8_t red,
                                         uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) stroke_round_rect_count += 1;
}
void elisa_skia_canvas_shadow_round_rect(size_t canvas, float x, float y, float width,
                                         float height, float radius, uint8_t alpha) {
    (void)x; (void)y; (void)width; (void)height; (void)radius; (void)alpha;
    if (canvas != 0) shadow_round_rect_count += 1;
}
void elisa_skia_canvas_draw_image(size_t canvas, size_t image, float x, float y,
                                  float width, float height, uint8_t alpha) {
    (void)image; (void)x; (void)y; (void)width; (void)height; (void)alpha;
    if (canvas != 0) image_count += 1;
}
void elisa_skia_canvas_draw_text_with_font(size_t canvas, size_t font, const char *text,
                                           size_t length, float x, float y, float size,
                                           uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)font; (void)text; (void)length; (void)x; (void)y; (void)size;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) text_count += 1;
}
void elisa_skia_canvas_fill_circle(size_t canvas, float x, float y, float radius,
                                   uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x; (void)y; (void)radius;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) circle_count += 1;
}
void elisa_skia_canvas_fill_triangle(size_t canvas, float ax, float ay, float bx, float by,
                                     float cx, float cy, uint8_t red, uint8_t green,
                                     uint8_t blue, uint8_t alpha) {
    (void)ax; (void)ay; (void)bx; (void)by; (void)cx; (void)cy;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) triangle_count += 1;
}
void elisa_skia_canvas_fill_line(size_t canvas, float x0, float y0, float x1, float y1,
                                 uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)x0; (void)y0; (void)x1; (void)y1;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) line_count += 1;
}
void elisa_skia_canvas_draw_text(size_t canvas, const char *text, size_t length,
                                 float x, float y, float size, uint8_t red,
                                 uint8_t green, uint8_t blue, uint8_t alpha) {
    (void)text; (void)length; (void)x; (void)y; (void)size;
    (void)red; (void)green; (void)blue; (void)alpha;
    if (canvas != 0) text_count += 1;
}

float elisa_skia_measure_text_width(const char *text, size_t length, float size) {
    return text == NULL ? 0.0f : (float)length * size * 0.5f;
}
float elisa_skia_font_ascent(float size) { return size * 0.8f; }
float elisa_skia_text_line_height(float size) { return size * 1.2f; }
float elisa_skia_measure_text_width_with_font(size_t font, const char *text, size_t length, float size) {
    return font == 0 || text == NULL ? 0.0f : (float)length * size * 0.6f;
}
float elisa_skia_font_ascent_with_font(size_t font, float size) { return font == 0 ? 0.0f : size * 0.85f; }
float elisa_skia_text_line_height_with_font(size_t font, float size) { return font == 0 ? 0.0f : size * 1.25f; }

void skia_test_reset(void) {
    save_count = 0; restore_count = 0; scale_count = 0; clip_count = 0;
    clear_count = 0; rect_count = 0; round_rect_count = 0; stroke_round_rect_count = 0; shadow_round_rect_count = 0; image_count = 0; circle_count = 0; triangle_count = 0;
    line_count = 0; text_count = 0; last_round_radius = 0.0f;
}
int skia_test_save_count(void) { return save_count; }
int skia_test_restore_count(void) { return restore_count; }
int skia_test_scale_count(void) { return scale_count; }
int skia_test_clip_count(void) { return clip_count; }
int skia_test_clear_count(void) { return clear_count; }
int skia_test_rect_count(void) { return rect_count; }
int skia_test_round_rect_count(void) { return round_rect_count; }
int skia_test_stroke_round_rect_count(void) { return stroke_round_rect_count; }
int skia_test_shadow_round_rect_count(void) { return shadow_round_rect_count; }
int skia_test_image_count(void) { return image_count; }
int skia_test_circle_count(void) { return circle_count; }
int skia_test_triangle_count(void) { return triangle_count; }
int skia_test_line_count(void) { return line_count; }
int skia_test_text_count(void) { return text_count; }
float skia_test_last_round_radius(void) { return last_round_radius; }
