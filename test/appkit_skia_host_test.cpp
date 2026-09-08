// Headless AppKit/Skia compositor fixture. No NSWindow is created or shown.

#include <CoreGraphics/CoreGraphics.h>

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <limits>

#include "../include/elisa_appkit_skia.h"

extern "C" void elisa_appkit_skia_test_force_failure(std::int32_t enabled);
extern "C" void elisa_appkit_skia_test_force_preframe_rejection(std::int32_t enabled);

namespace {

bool expect_rgba(const std::uint8_t* pixels, int row_bytes, int x, int y,
                std::uint8_t red, std::uint8_t green, std::uint8_t blue,
                const char* label) {
    const std::uint8_t* pixel = pixels + y * row_bytes + x * 4;
    if (pixel[0] == red && pixel[1] == green && pixel[2] == blue && pixel[3] == 255) return true;
    std::fprintf(stderr, "%s: expected rgba(%u,%u,%u,255), got rgba(%u,%u,%u,%u)\n",
                 label, red, green, blue, pixel[0], pixel[1], pixel[2], pixel[3]);
    return false;
}

bool expect_ink(const std::uint8_t* pixels, int row_bytes, int left, int top,
                int right, int bottom) {
    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            const std::uint8_t* pixel = pixels + y * row_bytes + x * 4;
            if (pixel[0] != 18 || pixel[1] != 24 || pixel[2] != 32 || pixel[3] != 255) return true;
        }
    }
    std::fprintf(stderr, "text: no rasterized glyphs in the CoreGraphics target\n");
    return false;
}

}  // namespace

int main() {
    constexpr int width = 320;
    constexpr int height = 200;
    constexpr int row_bytes = width * 4;
    const CGBitmapInfo bitmap_info = static_cast<CGBitmapInfo>(
        static_cast<std::uint32_t>(kCGImageAlphaPremultipliedLast) |
        static_cast<std::uint32_t>(kCGBitmapByteOrder32Big));
    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(nullptr, width, height, 8, row_bytes,
                                                  color_space, bitmap_info);
    CGColorSpaceRelease(color_space);
    if (context == nullptr) {
        std::fprintf(stderr, "appkit skia host: failed to create bitmap context\n");
        return 2;
    }

    const std::int32_t malformed_status = elisa_appkit_canvas_skia_present(
        0, reinterpret_cast<std::size_t>(context), 320.0f, 200.0f,
        std::numeric_limits<float>::max(), 1.0f);
    if (malformed_status != 0) {
        std::fprintf(stderr, "appkit skia host: accepted an out-of-range backing extent\n");
        CGContextRelease(context);
        return 3;
    }

    const std::int32_t status = elisa_appkit_canvas_skia_present(
        0, reinterpret_cast<std::size_t>(context), 320.0f, 200.0f,
        static_cast<float>(width), static_cast<float>(height));
    const auto* pixels = static_cast<const std::uint8_t*>(CGBitmapContextGetData(context));
    bool ok = status == 1 && pixels != nullptr;
    if (!ok) std::fprintf(stderr, "appkit skia host: compositor returned status %d\n", status);
    if (ok) ok = expect_rgba(pixels, row_bytes, 0, 0, 18, 24, 32, "background") && ok;
    if (ok) ok = expect_rgba(pixels, row_bytes, 40, 40, 220, 80, 100, "rounded fill") && ok;
    if (ok) ok = expect_rgba(pixels, row_bytes, 80, 130, 60, 180, 140, "circle") && ok;
    if (ok) ok = expect_rgba(pixels, row_bytes, 230, 50, 70, 120, 220, "triangle") && ok;
    if (ok) ok = expect_ink(pixels, row_bytes, 15, 158, 110, 198) && ok;

    // AppKit supplies a point-based CGContext whose device transform maps
    // logical view units to backing pixels. The compositor must draw into the
    // logical bounds, not pass the pixel dimensions as user-space geometry.
    constexpr int scaled_width = 640;
    constexpr int scaled_height = 400;
    constexpr int scaled_row_bytes = scaled_width * 4;
    CGColorSpaceRef scaled_color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef scaled_context = CGBitmapContextCreate(nullptr, scaled_width, scaled_height, 8,
                                                          scaled_row_bytes, scaled_color_space, bitmap_info);
    CGColorSpaceRelease(scaled_color_space);
    if (scaled_context == nullptr) {
        std::fprintf(stderr, "appkit skia host: failed to create scaled bitmap context\n");
        CGContextRelease(context);
        return 6;
    }
    CGContextScaleCTM(scaled_context, 2.0, 2.0);
    const std::int32_t scaled_status = elisa_appkit_canvas_skia_present(
        0, reinterpret_cast<std::size_t>(scaled_context), 320.0f, 200.0f,
        static_cast<float>(scaled_width), static_cast<float>(scaled_height));
    const auto* scaled_pixels = static_cast<const std::uint8_t*>(CGBitmapContextGetData(scaled_context));
    bool scaled_ok = scaled_status == 1 && scaled_pixels != nullptr;
    if (!scaled_ok) std::fprintf(stderr, "appkit skia host: scaled compositor returned status %d\n", scaled_status);
    if (scaled_ok) scaled_ok = expect_rgba(scaled_pixels, scaled_row_bytes, 0, 0, 18, 24, 32, "scaled background") && scaled_ok;
    if (scaled_ok) scaled_ok = expect_rgba(scaled_pixels, scaled_row_bytes, 80, 80, 220, 80, 100, "scaled rounded fill") && scaled_ok;
    if (scaled_ok) scaled_ok = expect_rgba(scaled_pixels, scaled_row_bytes, 160, 260, 60, 180, 140, "scaled circle") && scaled_ok;
    if (scaled_ok) scaled_ok = expect_rgba(scaled_pixels, scaled_row_bytes, 460, 100, 70, 120, 220, "scaled triangle") && scaled_ok;
    if (scaled_ok) scaled_ok = expect_ink(scaled_pixels, scaled_row_bytes, 30, 316, 220, 396) && scaled_ok;
    CGContextRelease(scaled_context);
    if (!scaled_ok) {
        CGContextRelease(context);
        return 7;
    }

    // A pre-frame rejection leaves the CoreGraphics target untouched and is
    // the only result that permits the Objective-C caller to run its fallback
    // path. This must remain distinct from a negative post-frame failure.
    CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    elisa_appkit_skia_test_force_preframe_rejection(1);
    const std::int32_t rejected_status = elisa_appkit_canvas_skia_present(
        0, reinterpret_cast<std::size_t>(context), 320.0f, 200.0f,
        static_cast<float>(width), static_cast<float>(height));
    elisa_appkit_skia_test_force_preframe_rejection(0);
    const auto* rejected_pixels = static_cast<const std::uint8_t*>(CGBitmapContextGetData(context));
    if (rejected_status != 0 || rejected_pixels == nullptr ||
        !expect_rgba(rejected_pixels, row_bytes, 0, 0, 0, 0, 0, "pre-frame rejection")) {
        std::fprintf(stderr, "appkit skia host: pre-frame rejection was not fallback-safe\n");
        CGContextRelease(context);
        return 8;
    }

    // The callback has already consumed app_frame before a late presentation
    // failure is known. Its negative status is distinct from the zero
    // pre-frame fallback result, and the borrowed CoreGraphics target remains
    // untouched so an AppKit caller cannot accidentally replay the frame.
    CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    elisa_appkit_skia_test_force_failure(1);
    const std::int32_t failed_status = elisa_appkit_canvas_skia_present(
        0, reinterpret_cast<std::size_t>(context), 320.0f, 200.0f,
        static_cast<float>(width), static_cast<float>(height));
    elisa_appkit_skia_test_force_failure(0);
    const auto* failed_pixels = static_cast<const std::uint8_t*>(CGBitmapContextGetData(context));
    if (failed_status >= 0 || failed_pixels == nullptr ||
        !expect_rgba(failed_pixels, row_bytes, 0, 0, 0, 0, 0, "post-frame failure")) {
        std::fprintf(stderr, "appkit skia host: post-frame failure was replayable\n");
        CGContextRelease(context);
        return 5;
    }
    CGContextRelease(context);
    if (!ok) return 4;
    std::printf("appkit skia host: off-screen CoreGraphics presentation passed\n");
    return 0;
}
