// Headless Skia host for the shipped hello showcase.
//
// The application workflow is driven inside Elisa; this host only supplies a
// raster surface and a borrowed CoreText typeface, then records pixels and
// timing as the real renderer evidence required by the build gate.

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkSurface.h"
#include "include/encode/SkPngEncoder.h"
#include "include/ports/SkFontMgr_mac_ct.h"
#include "include/core/SkStream.h"

extern "C" std::int32_t elisa_showcase_skia_prepare();
extern "C" std::int32_t elisa_showcase_skia_render(std::size_t canvas, std::size_t font);
extern "C" std::int32_t elisa_showcase_skia_command_count();
extern "C" std::int32_t elisa_showcase_skia_semantic_count();
extern "C" std::int32_t elisa_showcase_skia_art_count();
extern "C" std::int32_t elisa_showcase_skia_deferred_count();
extern "C" std::int32_t elisa_showcase_skia_probe_x();
extern "C" std::int32_t elisa_showcase_skia_probe_y();

namespace {

int configured_iterations() {
    const char* value = std::getenv("ELISA_UI_SKIA_RENDER_ITERATIONS");
    if (value == nullptr) return 16;
    const long parsed = std::strtol(value, nullptr, 10);
    return parsed > 0 && parsed <= 10000 ? static_cast<int>(parsed) : 16;
}

std::size_t count_color(const SkPixmap& pixels, SkColor expected,
                        int left, int top, int right, int bottom) {
    std::size_t count = 0;
    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            count += pixels.getColor(x, y) == expected ? 1u : 0u;
        }
    }
    return count;
}

bool expect_color(const SkPixmap& pixels, int x, int y, SkColor expected,
                  const char* label) {
    const SkColor actual = pixels.getColor(x, y);
    if (actual == expected) return true;
    std::fprintf(stderr, "%s: expected 0x%08x, got 0x%08x\n", label, expected, actual);
    return false;
}

}  // namespace

int main(int argc, char** argv) {
    const char* output = argc > 1 ? argv[1] : "/tmp/elisa-ui-skia-showcase.png";
    const std::int32_t workflow = elisa_showcase_skia_prepare();
    if (workflow != 0) {
        std::fprintf(stderr, "skia showcase: public workflow reported %d failures\n", workflow);
        return 2;
    }

    const auto font_manager = SkFontMgr_New_CoreText(nullptr);
    const auto typeface = font_manager == nullptr
        ? nullptr
        : font_manager->matchFamilyStyle(nullptr, SkFontStyle::Normal());
    if (typeface == nullptr) {
        std::fprintf(stderr, "skia showcase: failed to resolve the CoreText default typeface\n");
        return 3;
    }

    constexpr int width = 800;
    constexpr int height = 680;
    const SkImageInfo info = SkImageInfo::Make(
        width, height, kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        std::fprintf(stderr, "skia showcase: failed to create raster surface\n");
        return 4;
    }
    SkCanvas* canvas = surface->getCanvas();
    const std::size_t canvas_handle = reinterpret_cast<std::size_t>(canvas);
    const std::size_t font_handle = reinterpret_cast<std::size_t>(typeface.get());
    const std::int32_t status = elisa_showcase_skia_render(canvas_handle, font_handle);
    if (status != 1) {
        std::fprintf(stderr, "skia showcase: Elisa returned status %d\n", status);
        return 5;
    }

    const std::int32_t commands = elisa_showcase_skia_command_count();
    const std::int32_t semantics = elisa_showcase_skia_semantic_count();
    const std::int32_t art = elisa_showcase_skia_art_count();
    const std::int32_t deferred = elisa_showcase_skia_deferred_count();
    if (commands <= 20 || semantics <= 10 || art < 6 || deferred != 2) {
        std::fprintf(stderr, "skia showcase: incomplete Elisa frame commands=%d semantics=%d art=%d deferred=%d\n",
                     commands, semantics, art, deferred);
        return 6;
    }

    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) {
        std::fprintf(stderr, "skia showcase: raster pixels unavailable\n");
        return 7;
    }
    bool ok = true;
    ok = expect_color(pixels, 0, 0, SkColorSetARGB(255, 226, 231, 241), "light-theme background") && ok;
    const std::size_t accent_pixels = count_color(
        pixels, SkColorSetARGB(255, 204, 76, 92), 40, 180, width - 40, height - 20);
    if (accent_pixels < 100) {
        std::fprintf(stderr, "skia showcase: retained custom artwork produced only %zu accent pixels\n",
                     accent_pixels);
        ok = false;
    }

    // The showcase probe intentionally overlaps its streams. The first
    // deferred badge is orange, the retained divider covers its middle, and
    // the second deferred circle covers the divider. Checking all three
    // pixels proves that deferred work is ordered with retained commands, not
    // appended as an overlay after the frame.
    const int probe_x = elisa_showcase_skia_probe_x();
    const int probe_y = elisa_showcase_skia_probe_y();
    if (probe_x < 0 || probe_y < 0 || probe_x + 72 >= width || probe_y + 18 >= height) {
        std::fprintf(stderr, "skia showcase: deferred probe escaped the retained content bounds x=%d y=%d\n",
                     probe_x, probe_y);
        ok = false;
    } else {
        ok = expect_color(pixels, probe_x + 2, probe_y + 9,
                          SkColorSetARGB(255, 250, 140, 40), "deferred badge before retained") && ok;
        ok = expect_color(pixels, probe_x + 16, probe_y + 9,
                          SkColorSetARGB(255, 80, 200, 220), "retained divider between deferred") && ok;
        ok = expect_color(pixels, probe_x + 56, probe_y + 9,
                          SkColorSetARGB(255, 236, 100, 210), "deferred badge after retained") && ok;
    }

    const int iterations = configured_iterations();
    const auto render_start = std::chrono::steady_clock::now();
    for (int index = 0; index < iterations; ++index) {
        const std::int32_t repeated = elisa_showcase_skia_render(canvas_handle, font_handle);
        if (repeated != 1) {
            std::fprintf(stderr, "skia showcase: repeated render %d returned status %d\n", index, repeated);
            return 8;
        }
    }
    const auto render_finish = std::chrono::steady_clock::now();
    const auto total_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
        render_finish - render_start).count();
    const auto average_ns = total_ns / iterations;

    SkFILEWStream stream(output);
    SkPngEncoder::Options options;
    if (!SkPngEncoder::Encode(&stream, pixels, options) || !stream.bytesWritten()) {
        std::fprintf(stderr, "skia showcase: failed to write %s\n", output);
        return 9;
    }
    if (!ok) return 10;
    std::printf("skia showcase: rendered and verified %s commands=%d semantics=%d art=%d deferred=%d accent_pixels=%zu probe_x=%d probe_y=%d render_iterations=%d render_total_ns=%lld render_average_ns=%lld\n",
                output, commands, semantics, art, deferred, accent_pixels, probe_x, probe_y, iterations,
                static_cast<long long>(total_ns), static_cast<long long>(average_ns));
    return 0;
}
