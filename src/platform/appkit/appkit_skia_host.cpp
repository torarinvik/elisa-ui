// Optional AppKit presentation bridge for the Skia custom renderer.
//
// AppKit still owns the window and CGContext. Elisa prepares the retained
// command batch through the callback below; this host creates a temporary
// CPU-raster SkSurface, composites its pixels into the borrowed CGContext, and
// releases all Skia objects before returning. No native widget policy lives
// here, and no surface pointer crosses into Elisa except for one frame.

#include <CoreGraphics/CoreGraphics.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

#include "../../../include/elisa_appkit_skia.h"
#include "../../../include/elisa_skia.h"
#include "include/core/SkColor.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/ports/SkFontMgr_mac_ct.h"

extern "C" std::int32_t elisa_appkit_canvas_skia_replay(std::size_t window_handle,
                                                          std::size_t canvas,
                                                          float scale,
                                                          std::size_t font);

namespace {

bool valid_dimension(float value) {
    return std::isfinite(value) && value > 0.0f;
}

bool valid_context(CGContextRef context, float pixel_width, float pixel_height) {
    return context != nullptr && valid_dimension(pixel_width) && valid_dimension(pixel_height);
}

CGImageRef image_from_pixels(const SkPixmap& pixels) {
    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    if (color_space == nullptr) return nullptr;
    CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, pixels.addr(), pixels.computeByteSize(), nullptr);
    if (provider == nullptr) {
        CGColorSpaceRelease(color_space);
        return nullptr;
    }
    const CGBitmapInfo bitmap_info = static_cast<CGBitmapInfo>(
        static_cast<std::uint32_t>(kCGImageAlphaPremultipliedLast) |
        static_cast<std::uint32_t>(kCGBitmapByteOrder32Big));
    CGImageRef image = CGImageCreate(
        pixels.width(), pixels.height(), 8, 32, pixels.rowBytes(), color_space,
        bitmap_info, provider, nullptr, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(color_space);
    return image;
}

}  // namespace

extern "C" std::int32_t elisa_appkit_canvas_skia_present(std::size_t window_handle,
                                                           std::size_t context_handle,
                                                           float logical_width,
                                                           float logical_height,
                                                           float pixel_width_value,
                                                           float pixel_height_value) {
    CGContextRef context = reinterpret_cast<CGContextRef>(context_handle);
    if (!valid_context(context, pixel_width_value, pixel_height_value) || !valid_dimension(logical_width) ||
        !valid_dimension(logical_height)) {
        return 0;
    }

    const int pixel_width = static_cast<int>(std::lround(pixel_width_value));
    const int pixel_height = static_cast<int>(std::lround(pixel_height_value));
    if (pixel_width <= 0 || pixel_height <= 0) return 0;
    const float scale_x = static_cast<float>(pixel_width) / logical_width;
    const float scale_y = static_cast<float>(pixel_height) / logical_height;
    if (!valid_dimension(scale_x) || !valid_dimension(scale_y)) return 0;

    const SkImageInfo info = SkImageInfo::Make(
        pixel_width, pixel_height, kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (surface == nullptr) return 0;

    const auto font_manager = SkFontMgr_New_CoreText(nullptr);
    const auto typeface = font_manager == nullptr
        ? nullptr
        : font_manager->matchFamilyStyle(nullptr, SkFontStyle::Normal());
    if (typeface == nullptr) return 0;

    const std::int32_t status = elisa_appkit_canvas_skia_replay(
        window_handle, reinterpret_cast<std::size_t>(surface->getCanvas()),
        std::min(scale_x, scale_y), reinterpret_cast<std::size_t>(typeface.get()));
    if (status <= 0) return 0;

    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return 0;
    CGImageRef image = image_from_pixels(pixels);
    if (image == nullptr) return 0;
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, pixel_width, pixel_height), image);
    CGContextRestoreGState(context);
    CGImageRelease(image);
    return status;
}
