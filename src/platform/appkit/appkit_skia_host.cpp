// Optional AppKit presentation bridge for the Skia custom renderer.
//
// AppKit still owns the window and CGContext. Elisa prepares the retained
// command batch through the callback below; this host creates a temporary
// CPU-raster SkSurface, composites its pixels into the borrowed CGContext, and
// releases all Skia objects before returning. No native widget policy lives
// here, and no surface pointer crosses into Elisa except for one frame.

#include <CoreGraphics/CoreGraphics.h>

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
                                                          float logical_width,
                                                          float logical_height,
                                                          float pixel_width,
                                                          float pixel_height,
                                                          std::size_t font);

namespace {

bool valid_dimension(float value) {
    return std::isfinite(value) && value > 0.0f;
}

bool valid_context(CGContextRef context, float pixel_width, float pixel_height) {
    return context != nullptr && valid_dimension(pixel_width) && valid_dimension(pixel_height);
}

// The Elisa snapshot path already bounds bitmap extents before narrowing them
// to its i32 CoreGraphics ABI. Keep the optional compositor fail-closed for
// direct foreign callers too: never cast an out-of-range float to int or let a
// hostile pair request an unbounded temporary SkSurface allocation.
bool valid_pixel_extent(float value) {
    constexpr float max_extent = 2147483520.0f;  // largest safe f32 below 2^31
    return valid_dimension(value) && value <= max_extent;
}

bool valid_pixel_area(int width, int height) {
    constexpr std::size_t max_pixels = 67108864;
    return width > 0 && height > 0 && static_cast<std::size_t>(width) <=
        max_pixels / static_cast<std::size_t>(height);
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
        !valid_dimension(logical_height) || !valid_pixel_extent(pixel_width_value) ||
        !valid_pixel_extent(pixel_height_value)) {
        return 0;
    }

    const int pixel_width = static_cast<int>(std::lround(pixel_width_value));
    const int pixel_height = static_cast<int>(std::lround(pixel_height_value));
    if (!valid_pixel_area(pixel_width, pixel_height)) return 0;
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
        logical_width, logical_height,
        static_cast<float>(pixel_width), static_cast<float>(pixel_height),
        reinterpret_cast<std::size_t>(typeface.get()));
    // Zero is the explicit pre-frame rejection sentinel: Elisa did not enter
    // app_frame, so the Objective-C caller may use its CoreGraphics fallback.
    // A negative result means Elisa already consumed the frame (or native
    // presentation failed); never replay those callbacks through another
    // backend because application state may have changed synchronously.
    if (status == 0) return 0;
    if (status < 0) return status;

    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return -1;
    CGImageRef image = image_from_pixels(pixels);
    if (image == nullptr) return -1;
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    // AppKit's drawing context is expressed in view points; its device CTM
    // maps those points to the backing pixels. Draw the raster into the
    // logical view bounds so a Retina context does not scale the already
    // pixel-sized image a second time.
    CGContextDrawImage(context, CGRectMake(0, 0, logical_width, logical_height), image);
    CGContextRestoreGState(context);
    CGImageRelease(image);
    return status;
}
