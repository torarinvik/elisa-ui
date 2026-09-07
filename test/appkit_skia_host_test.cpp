// Headless AppKit/Skia compositor fixture. No NSWindow is created or shown.

#include <CoreGraphics/CoreGraphics.h>

#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "../include/elisa_appkit_skia.h"

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
    CGContextRelease(context);
    if (!ok) return 3;
    std::printf("appkit skia host: off-screen CoreGraphics presentation passed\n");
    return 0;
}
