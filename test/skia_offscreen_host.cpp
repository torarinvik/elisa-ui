// Real Skia CPU-raster host for the Elisa painter acceptance fixture.
// This is test-only: production hosts provide the same borrowed SkCanvas ABI.

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <limits>

#include "include/elisa_skia.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkTypeface.h"
#include "include/encode/SkPngEncoder.h"
#include "include/core/SkStream.h"
#include "include/ports/SkFontMgr_mac_ct.h"

extern "C" std::int32_t elisa_skia_offscreen_render(std::size_t canvas, std::size_t font);

namespace {

bool expect_color(const SkPixmap& pixels, int x, int y, SkColor expected, const char* label) {
    const SkColor actual = pixels.getColor(x, y);
    if (actual == expected) return true;
    std::fprintf(stderr, "%s: expected 0x%08x, got 0x%08x\n", label, expected, actual);
    return false;
}

bool expect_ink(const SkPixmap& pixels, int left, int top, int right, int bottom,
                SkColor background, const char* label) {
    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            if (pixels.getColor(x, y) != background) return true;
        }
    }
    std::fprintf(stderr, "%s: no rasterized glyphs in the expected region\n", label);
    return false;
}

}  // namespace

int main(int argc, char** argv) {
    const char* output = argc > 1 ? argv[1] : "/tmp/elisa-ui-skia-offscreen.png";
    const SkImageInfo info = SkImageInfo::Make(
        320, 200, kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        std::fprintf(stderr, "skia offscreen: failed to create raster surface\n");
        return 2;
    }

    // Direct foreign callers do not pass through Elisa's geometry helpers.
    // The native ABI must still fail closed for malformed values.
    SkCanvas* canvas = surface->getCanvas();
    canvas->clear(SkColorSetARGB(255, 18, 24, 32));
    const float nan = std::numeric_limits<float>::quiet_NaN();
    elisa_skia_canvas_fill_circle(reinterpret_cast<std::size_t>(canvas), 80.0f, 130.0f, -1.0f, 60, 180, 140, 255);
    elisa_skia_canvas_fill_round_rect(reinterpret_cast<std::size_t>(canvas), 20.0f, 20.0f, nan, 60.0f, 8.0f, 220, 80, 100, 255);
    elisa_skia_canvas_fill_line(reinterpret_cast<std::size_t>(canvas), 0.0f, nan, 20.0f, 20.0f, 1.0f, 240, 240, 245, 255);
    SkPixmap malformed_pixels;
    if (!surface->peekPixels(&malformed_pixels) ||
        !expect_color(malformed_pixels, 80, 130, SkColorSetARGB(255, 18, 24, 32), "malformed no-op")) {
        return 6;
    }

    const auto font_manager = SkFontMgr_New_CoreText(nullptr);
    const auto typeface = font_manager == nullptr
        ? nullptr
        : font_manager->matchFamilyStyle(nullptr, SkFontStyle::Normal());
    if (typeface == nullptr) {
        std::fprintf(stderr, "skia offscreen: failed to resolve the CoreText default typeface\n");
        return 7;
    }
    const std::int32_t status = elisa_skia_offscreen_render(
        reinterpret_cast<std::size_t>(canvas), reinterpret_cast<std::size_t>(typeface.get()));
    if (status != 1) {
        std::fprintf(stderr, "skia offscreen: Elisa returned status %d\n", status);
        return 3;
    }

    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) {
        std::fprintf(stderr, "skia offscreen: raster pixels unavailable\n");
        return 4;
    }
    bool ok = true;
    ok = expect_color(pixels, 0, 0, SkColorSetARGB(255, 18, 24, 32), "background") && ok;
    ok = expect_color(pixels, 40, 40, SkColorSetARGB(255, 220, 80, 100), "rounded fill") && ok;
    ok = expect_color(pixels, 80, 130, SkColorSetARGB(255, 60, 180, 140), "circle") && ok;
    ok = expect_color(pixels, 230, 50, SkColorSetARGB(255, 70, 120, 220), "triangle") && ok;
    ok = expect_ink(pixels, 15, 158, 110, 198, SkColorSetARGB(255, 18, 24, 32), "text") && ok;

    SkFILEWStream stream(output);
    SkPngEncoder::Options options;
    if (!SkPngEncoder::Encode(&stream, pixels, options) || !stream.bytesWritten()) {
        std::fprintf(stderr, "skia offscreen: failed to write %s\n", output);
        return 5;
    }
    if (!ok) return 6;
    std::printf("skia offscreen: rendered and verified %s\n", output);
    return 0;
}
