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

#include "../examples/storefront/pictures_skia.h"

extern "C" void elisa_skia_set_bold_typeface(std::size_t font);
extern "C" void elisa_skia_set_font_manager(std::size_t manager);
extern "C" std::int32_t elisa_storefront_skia_render(std::size_t canvas, std::size_t font,
                                                    float width, float height, float scale);
extern "C" std::int32_t elisa_storefront_skia_hover(std::int32_t pressed);
extern "C" std::int32_t elisa_storefront_skia_bind(std::size_t brand, std::size_t glyph,
                                                  std::size_t banner, std::size_t plate,
                                                  std::size_t grain);

namespace {

using elisa_storefront_pictures::make_glyph;
using elisa_storefront_pictures::make_grain;
using elisa_storefront_pictures::make_scene;

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

    // THE NULL FAMILY IS NOT THE SYSTEM FONT. Asked for no family at all,
    // CoreText answers Helvetica at weight 400 whatever style is requested,
    // so the "bold" face this host lent was the regular one and every heading
    // was drawn at regular weight. The system UI face has a name CoreText
    // matches, and its bold is bold.
    sk_sp<SkFontMgr> font_manager = SkFontMgr_New_CoreText(nullptr);
    sk_sp<SkTypeface> typeface =
        font_manager ? font_manager->matchFamilyStyle(".AppleSystemUIFont", SkFontStyle::Normal()) : nullptr;
    sk_sp<SkTypeface> bold =
        font_manager ? font_manager->matchFamilyStyle(".AppleSystemUIFont", SkFontStyle::Bold()) : nullptr;
    elisa_skia_set_bold_typeface(reinterpret_cast<std::size_t>(bold.get()));
    elisa_skia_set_font_manager(reinterpret_cast<std::size_t>(font_manager.get()));
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
        const SkColor c = pixels.getColor(static_cast<int>(1300 * scale), static_cast<int>(160 * scale));
        return static_cast<int>((SkColorGetR(c) * 54 + SkColorGetG(c) * 183 + SkColorGetB(c) * 19) >> 8);
    }();

    sk_sp<SkImage> banner = make_scene(720, 240, 150, 190, 250);
    sk_sp<SkImage> plate = make_scene(360, 180, 170, 160, 235);
    sk_sp<SkImage> brand = make_glyph();
    sk_sp<SkImage> glyph = make_glyph();
    sk_sp<SkImage> grain = make_grain();
    if (!banner || !plate || !brand || !glyph || !grain) {
        std::fprintf(stderr, "storefront skia: could not build the pictures\n");
        return 4;
    }
    if (elisa_storefront_skia_bind(reinterpret_cast<std::size_t>(brand.get()),
                                   reinterpret_cast<std::size_t>(glyph.get()),
                                   reinterpret_cast<std::size_t>(banner.get()),
                                   reinterpret_cast<std::size_t>(plate.get()),
                                   reinterpret_cast<std::size_t>(grain.get())) != 1) {
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
    const SkColor c = pixels.getColor(static_cast<int>(1300 * scale), static_cast<int>(160 * scale));
    const int lit = static_cast<int>((SkColorGetR(c) * 54 + SkColorGetG(c) * 183 + SkColorGetB(c) * 19) >> 8);
    if (bare < 0 || std::abs(lit - bare) < 20) {
        std::fprintf(stderr, "storefront skia: the plates never arrived (%d before, %d after)\n",
                     bare, lit);
        return 5;
    }

    // The primary action under the cursor, then held down. The lift, the
    // light and the recess are appearances a pointer produces, and a frame of
    // controls at rest shows none of them. Motion eases between the two, so
    // a frame is taken PER STEP: the first is mid-transition, a later one is
    // settled, and both are written. The settled ones must differ from rest
    // and from each other, or the pointer reached nothing.
    const auto luminance_at = [&](int px, int py) {
        SkPixmap p;
        if (!surface->peekPixels(&p)) return -1;
        const SkColor c = p.getColor(px, py);
        return static_cast<int>((SkColorGetR(c) * 54 + SkColorGetG(c) * 183 + SkColorGetB(c) * 19) >> 8);
    };
    const int rest = luminance_at(static_cast<int>(372 * scale), static_cast<int>(248 * scale));
    int settled[2] = {rest, rest};
    for (int state = 0; state < 2; ++state) {
        if (elisa_storefront_skia_hover(state) != 1) {
            std::fprintf(stderr, "storefront skia: could not move the pointer\n");
            return 7;
        }
        for (int step = 0; step < 6; ++step) {
            surface->getCanvas()->clear(SK_ColorTRANSPARENT);
            if (elisa_storefront_skia_render(reinterpret_cast<std::size_t>(surface->getCanvas()),
                                             reinterpret_cast<std::size_t>(typeface.get()),
                                             static_cast<float>(width), static_cast<float>(height), scale) != 1) {
                std::fprintf(stderr, "storefront skia: %s frame returned an error\n", state ? "pressed" : "hover");
                return 5;
            }
            if (step == 0) {
                const std::string mid = path.substr(0, path.size() - 4) + (state ? "-pressing.png" : "-hovering.png");
                write_png(surface.get(), mid);
            }
        }
        settled[state] = luminance_at(static_cast<int>(372 * scale), static_cast<int>(248 * scale));
        const std::string done = path.substr(0, path.size() - 4) + (state ? "-pressed.png" : "-hover.png");
        if (!write_png(surface.get(), done)) {
            std::fprintf(stderr, "storefront skia: failed to write %s\n", done.c_str());
            return 6;
        }
    }
    if (settled[0] == rest || settled[1] == settled[0]) {
        std::fprintf(stderr, "storefront skia: the pointer reached nothing (rest %d, hover %d, pressed %d)\n",
                     rest, settled[0], settled[1]);
        return 5;
    }
    std::printf("storefront skia: rendered %dx%d at %.1fx -> %s\n",
                static_cast<int>(width * scale), static_cast<int>(height * scale),
                static_cast<double>(scale), path.c_str());
    return 0;
}
