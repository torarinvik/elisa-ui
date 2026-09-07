// Real Skia CPU-raster host for the Elisa painter acceptance fixture.
// This is test-only: production hosts provide the same borrowed SkCanvas ABI.

#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "include/core/SkColor.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"
#include "include/encode/SkPngEncoder.h"
#include "include/core/SkStream.h"

extern "C" std::int32_t elisa_skia_offscreen_render(std::size_t canvas);

namespace {

bool expect_color(const SkPixmap& pixels, int x, int y, SkColor expected, const char* label) {
    const SkColor actual = pixels.getColor(x, y);
    if (actual == expected) return true;
    std::fprintf(stderr, "%s: expected 0x%08x, got 0x%08x\n", label, expected, actual);
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

    const std::int32_t status = elisa_skia_offscreen_render(
        reinterpret_cast<std::size_t>(surface->getCanvas()));
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
