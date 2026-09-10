// Off-screen host for the showcase application rendered by real Skia.
//
// It owns a raster surface and a system typeface and nothing else: which page
// to show, how it is laid out and every pixel of it are Elisa's. One PNG per
// page, so the renderer's output can be looked at rather than only asserted on.

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

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

extern "C" std::int32_t elisa_showcase_app_skia_render(std::size_t canvas, std::size_t font,
                                                       float width, float height, std::int32_t page);
extern "C" std::int32_t elisa_showcase_app_skia_focus_next();
extern "C" std::int32_t elisa_showcase_app_skia_toggle_theme();

namespace {

bool write_png(SkSurface* surface, const std::string& path) {
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return false;
    SkFILEWStream stream(path.c_str());
    return stream.isValid() && SkPngEncoder::Encode(&stream, pixels, {});
}

}  // namespace

int main(int argc, char** argv) {
    const int width = argc > 2 ? std::atoi(argv[2]) : 1180;
    const int height = argc > 3 ? std::atoi(argv[3]) : 800;
    const std::string prefix = argc > 1 ? argv[1] : "showcase";
    if (width < 320 || height < 240 || width > 4096 || height > 4096) {
        std::fprintf(stderr, "showcase skia: implausible surface %dx%d\n", width, height);
        return 2;
    }

    sk_sp<SkFontMgr> font_manager = SkFontMgr_New_CoreText(nullptr);
    sk_sp<SkTypeface> typeface =
        font_manager ? font_manager->matchFamilyStyle(nullptr, SkFontStyle::Normal()) : nullptr;
    if (!typeface) {
        std::fprintf(stderr, "showcase skia: no system typeface\n");
        return 3;
    }

    const SkImageInfo info = SkImageInfo::Make(width, height, kRGBA_8888_SkColorType,
                                               kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        std::fprintf(stderr, "showcase skia: no raster surface\n");
        return 4;
    }

    for (std::int32_t page = 1; page <= 5; ++page) {
        surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        const std::int32_t status = elisa_showcase_app_skia_render(
            reinterpret_cast<std::size_t>(surface->getCanvas()),
            reinterpret_cast<std::size_t>(typeface.get()),
            static_cast<float>(width), static_cast<float>(height), page);
        if (status != 1) {
            std::fprintf(stderr, "showcase skia: page %d returned status %d\n", page, status);
            return 5;
        }
        const std::string path = prefix + "-page" + std::to_string(page) + ".png";
        if (!write_png(surface.get(), path)) {
            std::fprintf(stderr, "showcase skia: failed to write %s\n", path.c_str());
            return 6;
        }
        std::printf("showcase skia: wrote %s\n", path.c_str());
    }

    // One more frame of the forms page with the keyboard focus moved onto a
    // control. Every page above renders with nothing focused, so the focus ring
    // -- the part of the appearance a keyboard user actually navigates by --
    // was never in a picture anyone could look at.
    if (elisa_showcase_app_skia_focus_next() != 1) {
        std::fprintf(stderr, "showcase skia: could not move focus\n");
        return 7;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t focused_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 2);
    if (focused_status != 1) {
        std::fprintf(stderr, "showcase skia: focused page returned status %d\n", focused_status);
        return 5;
    }
    const std::string focused_path = prefix + "-focus.png";
    if (!write_png(surface.get(), focused_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", focused_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", focused_path.c_str());

    // ...and the same page in the light palette. The depth policy has two
    // halves -- a light surface is lifted by the shadow it casts, a dark one by
    // light on its top edge -- and rendering only the dark theme left one of
    // them unexecuted and, worse, unlooked-at.
    if (elisa_showcase_app_skia_toggle_theme() != 1) {
        std::fprintf(stderr, "showcase skia: could not switch the palette\n");
        return 7;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t light_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 1);
    if (light_status != 1) {
        std::fprintf(stderr, "showcase skia: light page returned status %d\n", light_status);
        return 5;
    }
    const std::string light_path = prefix + "-light.png";
    if (!write_png(surface.get(), light_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", light_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", light_path.c_str());
    return 0;
}
