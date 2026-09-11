// The storefront's pictures, synthesised for a Skia host.
//
// The Skia fixture and the Android application both hand the composition
// its pictures as SkImages. They are MADE here rather than loaded, so neither
// host needs an asset on disk or a decoder: what is shown is that a
// composition built from the retained vocabulary looks like an interface, not
// that a PNG can be read. The CoreGraphics entry points draw the same scenes
// with their own painter's primitives, in pictures_cg.elisa.

#ifndef ELISA_STOREFRONT_PICTURES_SKIA_H_
#define ELISA_STOREFRONT_PICTURES_SKIA_H_

#include <cmath>
#include <cstdint>

#include "include/core/SkBitmap.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"

namespace elisa_storefront_pictures {

std::uint32_t pack(unsigned r, unsigned g, unsigned b, unsigned a = 255) {
    return static_cast<std::uint32_t>((a << 24) | (b << 16) | (g << 8) | r);
}

// A landscape with sky, hills and haze. Not art: enough structure that a
// blurred or missing plate is obvious, and enough colour that a card head
// reads as a picture rather than as a fill.
sk_sp<SkImage> make_scene(int width, int height, unsigned hue_r, unsigned hue_g, unsigned hue_b) {
    SkBitmap bitmap;
    if (!bitmap.tryAllocPixels(SkImageInfo::Make(width, height, kRGBA_8888_SkColorType,
                                                 kPremul_SkAlphaType))) {
        return nullptr;
    }
    for (int y = 0; y < height; ++y) {
        const double v = static_cast<double>(y) / height;
        for (int x = 0; x < width; ++x) {
            const double u = static_cast<double>(x) / width;
            // Sky: a vertical ramp toward the horizon.
            unsigned r = static_cast<unsigned>(hue_r * (0.45 + 0.55 * (1.0 - v)));
            unsigned g = static_cast<unsigned>(hue_g * (0.50 + 0.50 * (1.0 - v)));
            unsigned b = static_cast<unsigned>(hue_b * (0.60 + 0.40 * (1.0 - v)));
            // A sun low on the right: a soft radial bloom the ridges will cut
            // into, which is what gives the scene a light source and the
            // rest of the frame something to be lit by.
            const double sdx = (u - 0.72) * 1.6;
            const double sdy = (v - 0.34);
            const double sun = std::exp(-(sdx * sdx + sdy * sdy) * 22.0);
            r = static_cast<unsigned>(r + (255 - r) * sun * 0.9);
            g = static_cast<unsigned>(g + (255 - g) * sun * 0.7);
            b = static_cast<unsigned>(b + (255 - b) * sun * 0.35);
            // Cloud bands: two slow sines, brightened where they overlap.
            const double band = 0.5 + 0.5 * std::sin(u * 9.0 + v * 30.0) * std::sin(u * 3.5 - v * 11.0);
            const double cloud = v < 0.5 ? band * band * 0.28 : 0.0;
            r = static_cast<unsigned>(r + (255 - r) * cloud);
            g = static_cast<unsigned>(g + (255 - g) * cloud);
            b = static_cast<unsigned>(b + (255 - b) * cloud);
            // Two ridgelines, the far one hazed into the sky.
            const double far_ridge = 0.56 + 0.06 * std::sin(u * 7.0) + 0.03 * std::sin(u * 17.0);
            const double near_ridge = 0.72 + 0.10 * std::sin(u * 4.0 + 1.3);
            if (v > far_ridge) {
                r = static_cast<unsigned>(r * 0.62 + 30);
                g = static_cast<unsigned>(g * 0.70 + 44);
                b = static_cast<unsigned>(b * 0.66 + 40);
            }
            if (v > near_ridge) {
                r = static_cast<unsigned>(r * 0.44 + 14);
                g = static_cast<unsigned>(g * 0.56 + 28);
                b = static_cast<unsigned>(b * 0.50 + 22);
            }
            *bitmap.getAddr32(x, y) = pack(r > 255 ? 255 : r, g > 255 ? 255 : g, b > 255 ? 255 : b);
        }
    }
    bitmap.setImmutable();
    return bitmap.asImage();
}

// A mark: a rounded diamond in white on nothing, for the rail's tiles and the
// cards' marks. Transparent everywhere else so the tile's own ramp shows.
sk_sp<SkImage> make_glyph() {
    const int size = 48;
    SkBitmap bitmap;
    if (!bitmap.tryAllocPixels(SkImageInfo::Make(size, size, kRGBA_8888_SkColorType,
                                                 kPremul_SkAlphaType))) {
        return nullptr;
    }
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const double dx = std::abs(x - size / 2.0) / (size * 0.31);
            const double dy = std::abs(y - size / 2.0) / (size * 0.31);
            const double d = std::pow(dx, 2.4) + std::pow(dy, 2.4);
            const double edge = 1.0 - std::abs(d - 0.62) * 4.0;
            const unsigned a = static_cast<unsigned>(edge <= 0.0 ? 0.0 : (edge > 1.0 ? 235.0 : edge * 235.0));
            *bitmap.getAddr32(x, y) = pack(a, a, a, a);
        }
    }
    bitmap.setImmutable();
    return bitmap.asImage();
}

// GRAIN. A 64-pixel tile of blue-tinted noise, drawn over the page at a few
// percent. A mathematically smooth ramp reads as vector; this is what makes a
// background feel like a surface. Deterministic, so the frame is reproducible.
sk_sp<SkImage> make_grain() {
    const int size = 64;
    SkBitmap bitmap;
    if (!bitmap.tryAllocPixels(SkImageInfo::Make(size, size, kRGBA_8888_SkColorType, kPremul_SkAlphaType))) {
        return nullptr;
    }
    std::uint32_t seed = 0x9E3779B9u;
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
            const unsigned v = 160 + (seed % 96);
            *bitmap.getAddr32(x, y) = pack(v, v, v > 220 ? 255 : v + 24);
        }
    }
    bitmap.setImmutable();
    return bitmap.asImage();
}

}  // namespace elisa_storefront_pictures

#endif  // ELISA_STOREFRONT_PICTURES_SKIA_H_
