// Off-screen host for the storefront example rendered by real Skia.
//
// It owns a raster surface, a typeface and four pictures, and nothing else:
// every pixel of the layout is Elisa's. The pictures are MADE here rather than
// loaded, so the fixture needs no asset on disk and no decoder -- what is being
// shown is that a composition built from the retained vocabulary looks like an
// interface, not that a PNG can be read.

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "include/core/SkBitmap.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/encode/SkPngEncoder.h"
#include "include/ports/SkFontMgr_mac_ct.h"

extern "C" void elisa_skia_set_bold_typeface(std::size_t font);
extern "C" std::int32_t elisa_storefront_skia_render(std::size_t canvas, std::size_t font,
                                                    float width, float height, float scale);
extern "C" std::int32_t elisa_storefront_skia_bind(std::size_t brand, std::size_t glyph,
                                                  std::size_t banner, std::size_t plate);

namespace {

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

bool write_png(SkSurface* surface, const std::string& path) {
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return false;
    SkFILEWStream stream(path.c_str());
    if (!stream.isValid()) return false;
    return SkPngEncoder::Encode(&stream, pixels, SkPngEncoder::Options());
}

}  // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "/tmp/elisa-ui-storefront.png";
    const int width = argc > 2 ? std::atoi(argv[2]) : 1440;
    // The composition is as tall as it is: a hero, a section and two rows of
    // cards. Sizing the frame to it is the honest default -- stretching the
    // cards to fill a taller window would put a hole in every one of them.
    const int height = argc > 3 ? std::atoi(argv[3]) : 812;
    const float scale = argc > 4 ? static_cast<float>(std::atof(argv[4])) : 1.0f;

    sk_sp<SkFontMgr> font_manager = SkFontMgr_New_CoreText(nullptr);
    sk_sp<SkTypeface> typeface =
        font_manager ? font_manager->matchFamilyStyle(nullptr, SkFontStyle::Normal()) : nullptr;
    sk_sp<SkTypeface> bold =
        font_manager ? font_manager->matchFamilyStyle(nullptr, SkFontStyle::Bold()) : nullptr;
    elisa_skia_set_bold_typeface(reinterpret_cast<std::size_t>(bold.get()));
    if (!typeface) {
        std::fprintf(stderr, "storefront skia: no system typeface\n");
        return 3;
    }

    const SkImageInfo info = SkImageInfo::Make(static_cast<int>(width * scale),
                                               static_cast<int>(height * scale),
                                               kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        std::fprintf(stderr, "storefront skia: no raster surface\n");
        return 4;
    }

    // One frame so the application exists, then its pictures.
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    if (elisa_storefront_skia_render(reinterpret_cast<std::size_t>(surface->getCanvas()),
                                     reinterpret_cast<std::size_t>(typeface.get()),
                                     static_cast<float>(width), static_cast<float>(height),
                                     scale) != 1) {
        std::fprintf(stderr, "storefront skia: could not start the application\n");
        return 5;
    }
    // The HERO's sky, which is the one place a picture and the fill beneath it
    // are nothing like each other. A card plate sampled here would prove
    // nothing: its flat colour and its photograph are the same brightness by
    // design, so the check would pass with no picture at all.
    const int bare = [&] {
        SkPixmap pixels;
        if (!surface->peekPixels(&pixels)) return -1;
        const SkColor c = pixels.getColor(static_cast<int>(700 * scale), static_cast<int>(150 * scale));
        return static_cast<int>((SkColorGetR(c) * 54 + SkColorGetG(c) * 183 + SkColorGetB(c) * 19) >> 8);
    }();

    sk_sp<SkImage> banner = make_scene(720, 240, 150, 190, 250);
    sk_sp<SkImage> plate = make_scene(360, 180, 130, 180, 240);
    sk_sp<SkImage> brand = make_glyph();
    sk_sp<SkImage> glyph = make_glyph();
    if (!banner || !plate || !brand || !glyph) {
        std::fprintf(stderr, "storefront skia: could not build the pictures\n");
        return 4;
    }
    if (elisa_storefront_skia_bind(reinterpret_cast<std::size_t>(brand.get()),
                                   reinterpret_cast<std::size_t>(glyph.get()),
                                   reinterpret_cast<std::size_t>(banner.get()),
                                   reinterpret_cast<std::size_t>(plate.get())) != 1) {
        std::fprintf(stderr, "storefront skia: could not bind the pictures\n");
        return 5;
    }

    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t status = elisa_storefront_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), scale);
    if (status != 1) {
        std::fprintf(stderr, "storefront skia: frame returned status %d\n", status);
        return 5;
    }

    if (!write_png(surface.get(), path)) {
        std::fprintf(stderr, "storefront skia: failed to write %s\n", path.c_str());
        return 6;
    }

    // The card plates have to have ARRIVED. A frame with six coloured heads
    // where six pictures should be is a perfectly good PNG of the wrong thing.
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) {
        std::fprintf(stderr, "storefront skia: could not read the frame\n");
        return 5;
    }
    const SkColor c = pixels.getColor(static_cast<int>(700 * scale), static_cast<int>(150 * scale));
    const int lit = static_cast<int>((SkColorGetR(c) * 54 + SkColorGetG(c) * 183 + SkColorGetB(c) * 19) >> 8);
    if (bare < 0 || std::abs(lit - bare) < 20) {
        std::fprintf(stderr, "storefront skia: the plates never arrived (%d before, %d after)\n",
                     bare, lit);
        return 5;
    }

    std::printf("storefront skia: rendered %dx%d at %.1fx -> %s\n",
                static_cast<int>(width * scale), static_cast<int>(height * scale),
                static_cast<double>(scale), path.c_str());
    return 0;
}
