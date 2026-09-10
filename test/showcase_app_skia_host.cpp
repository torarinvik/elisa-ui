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
#include "include/core/SkBitmap.h"
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
extern "C" std::int32_t elisa_showcase_app_skia_direction(std::int32_t rtl);
extern "C" std::int32_t elisa_showcase_app_skia_page();
extern "C" std::int32_t elisa_showcase_app_skia_bind_image(std::size_t image);

namespace {

// The luminance of one pixel of the rendered frame. A frame is "light" or
// "dark" because of the APPLICATION's own surfaces, not because of the system
// tokens the framework resolves, and those are two different switches -- which
// is exactly what the light high-contrast frame got wrong.
int sampled_luminance(SkSurface* surface, int x, int y) {
    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) return -1;
    if (x < 0 || y < 0 || x >= pixels.width() || y >= pixels.height()) return -1;
    const SkColor color = pixels.getColor(x, y);
    return (SkColorGetR(color) * 54 + SkColorGetG(color) * 183 + SkColorGetB(color) * 19) >> 8;
}

// A picture for the application's mark, made here rather than loaded, so the
// fixture needs no asset on disk and no decoder: what is being proved is that
// an image reaches a retained widget, not that a PNG can be read. A diagonal
// ramp with a lighter wedge is enough to be recognisable at 34pt and enough to
// tell a drawn image from a fill of one colour.
sk_sp<SkImage> make_brand_image() {
    SkBitmap bitmap;
    if (!bitmap.tryAllocPixels(SkImageInfo::Make(64, 64, kRGBA_8888_SkColorType, kPremul_SkAlphaType))) {
        return nullptr;
    }
    for (int y = 0; y < 64; ++y) {
        for (int x = 0; x < 64; ++x) {
            const int ramp = (x + y) * 255 / 126;
            const bool wedge = (x + y) > 46 && (x + y) < 82 && x > 8 && x < 56;
            const unsigned r = static_cast<unsigned>(wedge ? 245 : 40 + ramp / 4);
            const unsigned g = static_cast<unsigned>(wedge ? 248 : 90 + ramp / 3);
            const unsigned b = static_cast<unsigned>(wedge ? 255 : 200 + ramp / 5);
            *bitmap.getAddr32(x, y) = static_cast<std::uint32_t>((255u << 24) | (b << 16) | (g << 8) | r);
        }
    }
    bitmap.setImmutable();
    return bitmap.asImage();
}

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

    // One frame first, so the application exists and can be handed a picture.
    // A resource is requested, marked ready and bound in that call; nothing
    // above it ever sees this SkImage.
    sk_sp<SkImage> brand = make_brand_image();
    if (!brand) {
        std::fprintf(stderr, "showcase skia: could not build the brand image\n");
        return 4;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    if (elisa_showcase_app_skia_render(
            reinterpret_cast<std::size_t>(surface->getCanvas()),
            reinterpret_cast<std::size_t>(typeface.get()),
            static_cast<float>(width), static_cast<float>(height), 1, 1.0f) != 1) {
        std::fprintf(stderr, "showcase skia: could not start the application\n");
        return 5;
    }
    if (elisa_showcase_app_skia_bind_image(reinterpret_cast<std::size_t>(brand.get())) != 1) {
        std::fprintf(stderr, "showcase skia: could not bind the brand image\n");
        return 5;
    }

    // The mark's pixel from the frame rendered BEFORE the bind above -- the
    // surface still holds it -- so the check below is a comparison rather
    // than a guess about what an empty tile looks like.
    const int tile_before = sampled_luminance(surface.get(), 32, 30);

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

    // The mark's own pixel, after the picture was bound. It is the first thing
    // in any frame this framework has rendered that is an image rather than a
    // shape, so nothing else could have covered for it. A binding that fails
    // silently, a command the painter drops, a reference that resolves to
    // nothing: each produces a perfectly good frame with an empty tile, which
    // is exactly what a size check cannot tell from a full one.
    const int tile_after = sampled_luminance(surface.get(), 32, 30);
    if (tile_before < 0 || tile_after < 0 || std::abs(tile_after - tile_before) < 40) {
        std::fprintf(stderr,
                     "showcase skia: the bound image never reached the frame "
                     "(%d before, %d after)\n", tile_before, tile_after);
        return 5;
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
    const int dark_contrast_luminance = sampled_luminance(surface.get(), width / 2, height / 2);
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
    // THE APPLICATION'S PALETTE IS NOT THE SYSTEM'S. `accessible(2)` resolves
    // the framework's tokens from a light system palette, and that is all it
    // does -- the showcase paints its own cards, panels and page from its own
    // theme, which the T key toggles. Without this the "light high-contrast"
    // frame rendered the framework's light tokens over the app's DARK
    // surfaces, so the two contrast frames had pixel-identical surfaces and
    // the light half of the depth policy -- which is weighted by each
    // surface's own lightness -- stayed unrendered under the name of the
    // frame that claimed to cover it.
    if (elisa_showcase_app_skia_toggle_theme() != 1 || elisa_showcase_app_skia_accessible(2) != 1) {
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
    // Two frames that merely DIFFER are not two palettes: these differed by
    // their control tokens alone for as long as they existed. The light one
    // has to be light.
    const int light_contrast_luminance = sampled_luminance(surface.get(), width / 2, height / 2);
    if (dark_contrast_luminance < 0 || light_contrast_luminance < 0) {
        std::fprintf(stderr, "showcase skia: could not sample the contrast frames\n");
        return 5;
    }
    if (light_contrast_luminance <= dark_contrast_luminance + 40) {
        std::fprintf(stderr,
                     "showcase skia: the light high-contrast frame is not lighter than the dark one "
                     "(%d vs %d); the application palette did not switch\n",
                     light_contrast_luminance, dark_contrast_luminance);
        return 5;
    }
    const std::string light_contrast_path = prefix + "-contrast-light.png";
    if (!write_png(surface.get(), light_contrast_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", light_contrast_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", light_contrast_path.c_str());
    if (elisa_showcase_app_skia_toggle_theme() != 1 || elisa_showcase_app_skia_accessible(0) != 1) {
        std::fprintf(stderr, "showcase skia: could not restore the default preferences\n");
        return 7;
    }

    // ...and the reading direction. Every mirrored coordinate in this
    // framework is asserted headlessly and appears in no picture, which is the
    // same shape as every other defect found here. This frame is where a
    // marker on the wrong side of its label is obvious at a glance.
    if (elisa_showcase_app_skia_direction(1) != 1) {
        std::fprintf(stderr, "showcase skia: could not select a right-to-left locale\n");
        return 7;
    }
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    const std::int32_t rtl_status = elisa_showcase_app_skia_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()),
        reinterpret_cast<std::size_t>(typeface.get()),
        static_cast<float>(width), static_cast<float>(height), 2, 1.0f);
    if (rtl_status != 1) {
        std::fprintf(stderr, "showcase skia: right-to-left page returned status %d\n", rtl_status);
        return 5;
    }
    const std::string rtl_path = prefix + "-rtl.png";
    if (!write_png(surface.get(), rtl_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", rtl_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", rtl_path.c_str());
    if (elisa_showcase_app_skia_direction(0) != 1) {
        std::fprintf(stderr, "showcase skia: could not restore the default locale\n");
        return 7;
    }

    // Back to the dark palette, then the confirmation dialog: a raised sheet
    // over a shell disabled beneath it. Modals are their own rendering case and
    // appeared in none of the frames above.
    //
    // The SAME page, undimmed, sampled well away from where the sheet will
    // land. It has to be the same page: the surface still holds the
    // right-to-left frame at this point, and comparing a mirrored shell
    // against an unmirrored one measures the mirroring, not the wash.
    //
    // A modal that leaves the page behind it fully lit is a band in the
    // layout above a shell that still looks clickable, which is what every
    // frame of this dialog showed until the framework grew an overlay layer.
    //
    // Honest about what this catches: the showcase ALSO disables its shell
    // while a modal is open, and disabled surfaces mute, so this fires if the
    // page behind the sheet stops receding for EITHER reason. It is not proof
    // that a scrim was laid -- that is asserted at the command level in
    // widget_layout_geometry_test, where the wash can be removed and watched
    // to fail. Measured here, the two together take the shell from 35 to 11.
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    if (elisa_showcase_app_skia_render(
            reinterpret_cast<std::size_t>(surface->getCanvas()),
            reinterpret_cast<std::size_t>(typeface.get()),
            static_cast<float>(width), static_cast<float>(height), 0, 1.0f) != 1) {
        std::fprintf(stderr, "showcase skia: could not render the undimmed shell\n");
        return 5;
    }
    const int undimmed_shell = sampled_luminance(surface.get(), width / 8, height - height / 8);
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
    const int dimmed_shell = sampled_luminance(surface.get(), width / 8, height - height / 8);
    if (undimmed_shell < 0 || dimmed_shell < 0) {
        std::fprintf(stderr, "showcase skia: could not sample the shell\n");
        return 5;
    }
    if (dimmed_shell >= undimmed_shell) {
        std::fprintf(stderr,
                     "showcase skia: the shell behind the modal is not dimmed (%d vs %d); "
                     "the sheet is a band in the layout, not an overlay\n",
                     dimmed_shell, undimmed_shell);
        return 5;
    }
    const std::string dialog_path = prefix + "-dialog.png";
    if (!write_png(surface.get(), dialog_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", dialog_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", dialog_path.c_str());

    // THE MODAL HAS TO GO FIRST. The retina frame is only worth anything as a
    // COMPARISON with the 1x frame of the same page, and it was being rendered
    // with the dialog still open: a modal over a shell the application had
    // disabled, on whichever page the dialog had been opened from, since a
    // modal consumes the page shortcuts too. Every pixel in it was dimmed by
    // the scrim and the disable, so nothing in it could be compared with
    // anything. It was checked only for its file size, which a frame of the
    // wrong page at the wrong brightness passes easily.
    if (elisa_showcase_app_skia_close_dialog() != 1) {
        std::fprintf(stderr, "showcase skia: could not close the dialog\n");
        return 7;
    }

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
    // The 1x reference for the comparison below has to be the SAME page, taken
    // now: the surface still holds the dialog frame, and the pages rendered at
    // the top of this run were taken before the palette, the accessibility
    // preferences and the locale had been moved around and put back.
    surface->getCanvas()->clear(SK_ColorTRANSPARENT);
    if (elisa_showcase_app_skia_render(
            reinterpret_cast<std::size_t>(surface->getCanvas()),
            reinterpret_cast<std::size_t>(typeface.get()),
            static_cast<float>(width), static_cast<float>(height), 1, 1.0f) != 1) {
        std::fprintf(stderr, "showcase skia: could not render the 1x reference frame\n");
        return 5;
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
    // ...and that it went where it was told. A page is selected by pressing
    // its shortcut, and a modal consumes every one of them, so a frame can
    // silently be of another page entirely -- which this one was, for as long
    // as it existed.
    if (elisa_showcase_app_skia_page() != 1) {
        std::fprintf(stderr,
                     "showcase skia: the retina frame is of page %d, not the page it asked for; "
                     "something consumed the shortcut\n", elisa_showcase_app_skia_page());
        return 5;
    }
    // THE POINT OF THE FRAME IS THAT IT IS THE SAME PICTURE. Sampling the same
    // LOGICAL point in both and requiring them to agree is the check the file
    // size was standing in for -- and the one that would have caught the
    // frame being of another page entirely.
    bool retina_matches = true;
    for (int step = 1; step <= 3; ++step) {
        const int x = width * step / 4;
        const int y = height * step / 4;
        const int one = sampled_luminance(surface.get(), x, y);
        const int two = sampled_luminance(retina.get(), x * 2, y * 2);
        if (one < 0 || two < 0 || std::abs(one - two) > 12) {
            std::fprintf(stderr,
                         "showcase skia: the retina frame is not the 1x frame at twice the pixels "
                         "(logical %d,%d: %d vs %d)\n", x, y, one, two);
            retina_matches = false;
        }
    }
    if (!retina_matches) return 5;
    const std::string retina_path = prefix + "-retina.png";
    if (!write_png(retina.get(), retina_path)) {
        std::fprintf(stderr, "showcase skia: failed to write %s\n", retina_path.c_str());
        return 6;
    }
    std::printf("showcase skia: wrote %s\n", retina_path.c_str());

    // A control under the cursor, and the same control held down. Every frame
    // above is of controls at rest, so the two appearances a pointer actually
    // produces were in no picture at all. The dialog is already closed: the
    // retina frame needed it gone before it, for the same reason.)
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
