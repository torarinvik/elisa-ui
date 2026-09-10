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

extern "C" void elisa_skia_set_bold_typeface(std::size_t font);
extern "C" std::int32_t elisa_showcase_app_skia_render(std::size_t canvas, std::size_t font,
                                                       float width, float height, std::int32_t page,
                                                       float scale);
extern "C" std::int32_t elisa_showcase_app_skia_focus_next();
extern "C" std::int32_t elisa_showcase_app_skia_toggle_theme();
extern "C" std::int32_t elisa_showcase_app_skia_accessible(std::int32_t mode);
extern "C" std::int32_t elisa_showcase_app_skia_open_dialog();
extern "C" std::int32_t elisa_showcase_app_skia_hover_button(std::int32_t pressed);
extern "C" std::int32_t elisa_showcase_app_skia_close_dialog();

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
    // The system bold face, lent for the life of the host: weighted runs are
    // drawn and measured with a designed bold instead of a synthetic stroke.
    sk_sp<SkTypeface> bold_typeface =
        font_manager ? font_manager->matchFamilyStyle(nullptr, SkFontStyle::Bold()) : nullptr;
    elisa_skia_set_bold_typeface(reinterpret_cast<std::size_t>(bold_typeface.get()));
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
            static_cast<float>(width), static_cast<float>(height), page, 1.0f);
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
        static_cast<float>(width), static_cast<float>(height), 2, 1.0f);
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
        static_cast<float>(width), static_cast<float>(height), 1, 1.0f);
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

    // ...and the accessibility branch, which no frame in this set had ever put
    // on screen: the high-contrast palette at double text scale. Every bug
    // found in that path so far was found by reading rather than by looking.
    if (elisa_showcase_app_skia_toggle_theme() != 1 || elisa_showcase_app_skia_accessible(1) != 1) {
        std::fprintf(stderr, "showcase skia: could not apply the accessible preferences\n");
        return 7;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t contrast_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 2, 1.0f);
    if (contrast_status != 1) {
        std::fprintf(stderr, "showcase skia: contrast page returned status %d\n", contrast_status);
        return 5;
    }
    const std::string contrast_path = prefix + "-contrast.png";
    if (!write_png(surface.get(), contrast_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", contrast_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", contrast_path.c_str());
    // ...and the same branch on the light palette. The depth policy is weighted
    // by each surface's own lightness, so the two high-contrast modes do not
    // exercise the same arithmetic -- and every bug found in this framework's
    // light palette so far was one the dark one hid.
    if (elisa_showcase_app_skia_accessible(2) != 1) {
        std::fprintf(stderr, "showcase skia: could not apply the light accessible preferences\n");
        return 7;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t light_contrast_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 2, 1.0f);
    if (light_contrast_status != 1) {
        std::fprintf(stderr, "showcase skia: light contrast page returned status %d\n", light_contrast_status);
        return 5;
    }
    const std::string light_contrast_path = prefix + "-contrast-light.png";
    if (!write_png(surface.get(), light_contrast_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", light_contrast_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", light_contrast_path.c_str());
    if (elisa_showcase_app_skia_accessible(0) != 1) {
        std::fprintf(stderr, "showcase skia: could not restore the default preferences\n");
        return 7;
    }

    // Back to the dark palette, then the confirmation dialog: a raised sheet
    // over a shell disabled beneath it. Modals are their own rendering case and
    // appeared in none of the frames above.
    if (elisa_showcase_app_skia_open_dialog() != 1) {
        std::fprintf(stderr, "showcase skia: could not open the dialog\n");
        return 7;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t dialog_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 0, 1.0f);
    if (dialog_status != 1) {
        std::fprintf(stderr, "showcase skia: dialog frame returned status %d\n", dialog_status);
        return 5;
    }
    const std::string dialog_path = prefix + "-dialog.png";
    if (!write_png(surface.get(), dialog_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", dialog_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", dialog_path.c_str());

    // And once at a RETINA backing scale: the same logical point extent on a
    // canvas with twice the pixels, which is what most Macs actually run. It is
    // where a renderer's radii, hairlines and glyph placement show whether they
    // were derived or merely tuned to look right at 1.0.
    const SkImageInfo retina_info = SkImageInfo::Make(width * 2, height * 2, kRGBA_8888_SkColorType,
                                                     kPremul_SkAlphaType);
    sk_sp<SkSurface> retina = SkSurfaces::Raster(retina_info);
    if (!retina) {
        std::fprintf(stderr, "showcase skia: no retina raster surface\n");
        return 4;
    }
    retina->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t retina_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(retina->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 1, 2.0f);
    if (retina_status != 1) {
        std::fprintf(stderr, "showcase skia: retina frame returned status %d\n", retina_status);
        return 5;
    }
    const std::string retina_path = prefix + "-retina.png";
    if (!write_png(retina.get(), retina_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", retina_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", retina_path.c_str());

    // A control under the cursor, and the same control held down. Every frame
    // above is of controls at rest, so the two appearances a pointer actually
    // produces were in no picture at all.
    if (elisa_showcase_app_skia_close_dialog() != 1) {
        std::fprintf(stderr, "showcase skia: could not close the dialog\n");
        return 7;
    }
    for (int pressed = 0; pressed < 2; ++pressed) {
        if (elisa_showcase_app_skia_hover_button(pressed) != 1) {
            std::fprintf(stderr, "showcase skia: could not put the pointer on a control\n");
            return 7;
        }
        surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        const std::int32_t pointer_status = elisa_showcase_app_skia_render(
            reinterpret_cast<std::size_t>(surface->getCanvas()),
            reinterpret_cast<std::size_t>(typeface.get()),
            static_cast<float>(width), static_cast<float>(height), 1, 1.0f);
        if (pointer_status != 1) {
            std::fprintf(stderr, "showcase skia: pointer frame returned status %d\n", pointer_status);
            return 5;
        }
        const std::string pointer_path = prefix + (pressed != 0 ? "-pressed.png" : "-hover.png");
        if (!write_png(surface.get(), pointer_path)) {
            std::fprintf(stderr, "showcase skia: failed to write %s\n", pointer_path.c_str());
            return 6;
        }
        std::printf("showcase skia: wrote %s\n", pointer_path.c_str());
    }
    return 0;
}
