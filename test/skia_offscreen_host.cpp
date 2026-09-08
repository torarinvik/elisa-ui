// Real Skia CPU-raster host for the Elisa painter acceptance fixture.
// This is test-only: production hosts provide the same borrowed SkCanvas ABI.

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <limits>

#include "include/elisa_skia.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkTypeface.h"
#include "include/encode/SkPngEncoder.h"
#include "include/core/SkStream.h"
#include "include/ports/SkFontMgr_mac_ct.h"

extern "C" std::int32_t elisa_skia_offscreen_render(std::size_t canvas, std::size_t font);

namespace {

bool expect_color(const SkPixmap& pixels, int x, int y, SkColor expected, const char* label) {
    const SkColor actual = pixels.getColor(x, y);
    if (actual == expected) return true;
    std::fprintf(stderr, "%s: expected 0x%08x, got 0x%08x\n", label, expected, actual);
    return false;
}

bool expect_color_near(const SkPixmap& pixels, int x, int y, SkColor expected,
                       int tolerance, const char* label) {
    const SkColor actual = pixels.getColor(x, y);
    const int red_delta = std::abs(static_cast<int>(SkColorGetR(actual)) - static_cast<int>(SkColorGetR(expected)));
    const int green_delta = std::abs(static_cast<int>(SkColorGetG(actual)) - static_cast<int>(SkColorGetG(expected)));
    const int blue_delta = std::abs(static_cast<int>(SkColorGetB(actual)) - static_cast<int>(SkColorGetB(expected)));
    if (red_delta <= tolerance && green_delta <= tolerance && blue_delta <= tolerance &&
        SkColorGetA(actual) == SkColorGetA(expected)) return true;
    std::fprintf(stderr, "%s: expected near 0x%08x, got 0x%08x\n", label, expected, actual);
    return false;
}

bool expect_ink(const SkPixmap& pixels, int left, int top, int right, int bottom,
                SkColor background, const char* label) {
    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            if (pixels.getColor(x, y) != background) return true;
        }
    }
    std::fprintf(stderr, "%s: no rasterized glyphs in the expected region\n", label);
    return false;
}

// Hash logical pixels rather than row padding so the value is stable across
// SkSurface row-byte choices. Repeated renders must reproduce this digest;
// otherwise a leaked save/clip/transform scope could silently alter frames.
std::uint64_t pixel_digest(const SkPixmap& pixels) {
    std::uint64_t hash = UINT64_C(1469598103934665603);
    for (int y = 0; y < pixels.height(); ++y) {
        for (int x = 0; x < pixels.width(); ++x) {
            hash ^= static_cast<std::uint32_t>(pixels.getColor(x, y));
            hash *= UINT64_C(1099511628211);
        }
    }
    return hash;
}

}  // namespace

int main(int argc, char** argv) {
    const char* output = argc > 1 ? argv[1] : "/tmp/elisa-ui-skia-offscreen.png";
    const SkImageInfo info = SkImageInfo::Make(
        320, 200, kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        std::fprintf(stderr, "skia offscreen: failed to create raster surface\n");
        return 2;
    }

    // Direct foreign callers do not pass through Elisa's geometry helpers.
    // The native ABI must still fail closed for malformed values.
    SkCanvas* canvas = surface->getCanvas();
    canvas->clear(SkColorSetARGB(255, 18, 24, 32));
    const float nan = std::numeric_limits<float>::quiet_NaN();
    const float hostile = std::numeric_limits<float>::max();
    elisa_skia_canvas_scale(reinterpret_cast<std::size_t>(canvas), 0.0f, 1.0f);
    elisa_skia_canvas_scale(reinterpret_cast<std::size_t>(canvas), hostile, 1.0f);
    elisa_skia_canvas_translate(reinterpret_cast<std::size_t>(canvas), nan, 0.0f);
    elisa_skia_canvas_translate(reinterpret_cast<std::size_t>(canvas), hostile, 0.0f);
    elisa_skia_canvas_rotate(reinterpret_cast<std::size_t>(canvas), nan);
    elisa_skia_canvas_rotate(reinterpret_cast<std::size_t>(canvas), hostile);
    elisa_skia_canvas_fill_circle(reinterpret_cast<std::size_t>(canvas), 80.0f, 130.0f, -1.0f, 60, 180, 140, 255);
    elisa_skia_canvas_fill_circle(reinterpret_cast<std::size_t>(canvas), hostile, 130.0f, 10.0f, 60, 180, 140, 255);
    elisa_skia_canvas_fill_circle(reinterpret_cast<std::size_t>(canvas), 16777216.0f, 130.0f, 1.0f, 60, 180, 140, 255);
    elisa_skia_canvas_stroke_circle(reinterpret_cast<std::size_t>(canvas), -16777216.0f, 130.0f, 1.0f, 1.0f, 60, 180, 140, 255);
    elisa_skia_canvas_stroke_circle(reinterpret_cast<std::size_t>(canvas), 16777215.0f, 130.0f, 1.0f, 4.0f, 60, 180, 140, 255);
    elisa_skia_canvas_fill_round_rect(reinterpret_cast<std::size_t>(canvas), 20.0f, 20.0f, nan, 60.0f, 8.0f, 220, 80, 100, 255);
    elisa_skia_canvas_fill_round_rect(reinterpret_cast<std::size_t>(canvas), hostile, 20.0f, 60.0f, 40.0f, 8.0f, 220, 80, 100, 255);
    elisa_skia_canvas_fill_round_rect(reinterpret_cast<std::size_t>(canvas), 20.0f, 20.0f, 60.0f, 40.0f, hostile, 220, 80, 100, 255);
    elisa_skia_canvas_fill_round_rect(reinterpret_cast<std::size_t>(canvas), 16777216.0f, 20.0f, 4.0f, 40.0f, 2.0f, 220, 80, 100, 255);
    elisa_skia_canvas_draw_image_source_sampling(reinterpret_cast<std::size_t>(canvas), 1,
                                                 -1.0f, 0.0f, 4.0f, 4.0f,
                                                 20.0f, 20.0f, 40.0f, 40.0f, 255, 1);
    elisa_skia_canvas_stroke_round_rect(reinterpret_cast<std::size_t>(canvas), 20.0f, 20.0f, 60.0f, 40.0f, 8.0f, hostile, 220, 80, 100, 255);
    elisa_skia_canvas_shadow_round_rect(reinterpret_cast<std::size_t>(canvas), 20.0f, 20.0f, 60.0f, 40.0f, 8.0f, 0.0f, 0.0f, hostile, 255);
    elisa_skia_canvas_fill_linear_gradient(reinterpret_cast<std::size_t>(canvas), 20.0f, 20.0f, hostile, 40.0f,
                                           20, 40, 80, 255, 100, 180, 220, 255, 1);
    elisa_skia_canvas_clip_rect(reinterpret_cast<std::size_t>(canvas), 0.0f, 0.0f, hostile, 100.0f);
    elisa_skia_canvas_draw_text(reinterpret_cast<std::size_t>(canvas), "x", 1, 20.0f, 40.0f, hostile, 255, 255, 255, 255);
    elisa_skia_canvas_fill_line(reinterpret_cast<std::size_t>(canvas), 0.0f, nan, 20.0f, 20.0f, 1.0f, 240, 240, 245, 255);
    SkPixmap malformed_pixels;
    if (elisa_skia_measure_text_width("x", 1, hostile) != 0.0f ||
        elisa_skia_font_ascent(hostile) != 0.0f || elisa_skia_text_line_height(hostile) != 0.0f ||
        !surface->peekPixels(&malformed_pixels) ||
        !expect_color(malformed_pixels, 80, 130, SkColorSetARGB(255, 18, 24, 32), "malformed no-op")) {
        return 6;
    }

    const auto font_manager = SkFontMgr_New_CoreText(nullptr);
    const auto typeface = font_manager == nullptr
        ? nullptr
        : font_manager->matchFamilyStyle(nullptr, SkFontStyle::Normal());
    if (typeface == nullptr) {
        std::fprintf(stderr, "skia offscreen: failed to resolve the CoreText default typeface\n");
        return 7;
    }
    const std::int32_t status = elisa_skia_offscreen_render(
        reinterpret_cast<std::size_t>(canvas), reinterpret_cast<std::size_t>(typeface.get()));
    if (status != 1) {
        std::fprintf(stderr, "skia offscreen: Elisa returned status %d\n", status);
        return 3;
    }

    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) {
        std::fprintf(stderr, "skia offscreen: raster pixels unavailable\n");
        return 4;
    }
    bool ok = true;
    ok = expect_color(pixels, 0, 0, SkColorSetARGB(255, 18, 24, 32), "background") && ok;
    ok = expect_color(pixels, 40, 40, SkColorSetARGB(255, 220, 80, 100), "rounded fill") && ok;
    ok = expect_color(pixels, 80, 130, SkColorSetARGB(255, 60, 180, 140), "circle") && ok;
    ok = expect_color(pixels, 230, 50, SkColorSetARGB(255, 70, 120, 220), "triangle") && ok;
    ok = expect_color(pixels, 120, 130, SkColorSetARGB(255, 20, 40, 80), "gradient start") && ok;
    ok = expect_color_near(pixels, 219, 130, SkColorSetARGB(255, 100, 180, 220), 2, "gradient end") && ok;
    ok = expect_ink(pixels, 15, 158, 110, 198, SkColorSetARGB(255, 18, 24, 32), "text") && ok;
    const std::uint64_t initial_digest = pixel_digest(pixels);

    int iterations = 16;
    if (const char* configured = std::getenv("ELISA_UI_SKIA_RENDER_ITERATIONS")) {
        const long parsed = std::strtol(configured, nullptr, 10);
        if (parsed > 0 && parsed <= 10000) iterations = static_cast<int>(parsed);
    }
    const auto render_start = std::chrono::steady_clock::now();
    for (int index = 0; index < iterations; ++index) {
        const std::int32_t repeated_status = elisa_skia_offscreen_render(
            reinterpret_cast<std::size_t>(canvas), reinterpret_cast<std::size_t>(typeface.get()));
        if (repeated_status != 1) {
            std::fprintf(stderr, "skia offscreen: repeated render %d returned status %d\n", index, repeated_status);
            return 8;
        }
    }
    const auto render_finish = std::chrono::steady_clock::now();
    const auto render_total_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(render_finish - render_start).count();
    const auto render_average_ns = render_total_ns / iterations;
    if (render_total_ns <= 0 || render_average_ns <= 0) {
        std::fprintf(stderr, "skia offscreen: renderer timing did not produce a positive sample\n");
        return 9;
    }
    const std::uint64_t repeated_digest = pixel_digest(pixels);
    if (repeated_digest != initial_digest) {
        std::fprintf(stderr,
                     "skia offscreen: repeated replay changed the pixel digest "
                     "(initial=%016llx repeated=%016llx)\n",
                     static_cast<unsigned long long>(initial_digest),
                     static_cast<unsigned long long>(repeated_digest));
        return 10;
    }

    SkFILEWStream stream(output);
    SkPngEncoder::Options options;
    if (!SkPngEncoder::Encode(&stream, pixels, options) || !stream.bytesWritten()) {
        std::fprintf(stderr, "skia offscreen: failed to write %s\n", output);
        return 5;
    }
    if (!ok) return 6;
    std::printf("skia offscreen: rendered and verified %s render_iterations=%d render_total_ns=%lld render_average_ns=%lld pixel_digest=%016llx\n",
                output, iterations, static_cast<long long>(render_total_ns),
                static_cast<long long>(render_average_ns),
                static_cast<unsigned long long>(repeated_digest));
    return 0;
}
