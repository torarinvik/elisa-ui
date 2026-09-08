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
#include "include/core/SkImage.h"
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
extern "C" std::int32_t elisa_showcase_skia_text_field_x();
extern "C" std::int32_t elisa_showcase_skia_text_field_y();
extern "C" std::int32_t elisa_showcase_skia_text_field_width();
extern "C" std::int32_t elisa_showcase_skia_text_field_height();
extern "C" std::int32_t elisa_showcase_skia_bind_resource_image(std::size_t image);
extern "C" std::int32_t elisa_showcase_skia_resource_probe_count();
extern "C" std::int32_t elisa_showcase_skia_resource_probe_x();
extern "C" std::int32_t elisa_showcase_skia_resource_probe_y();
extern "C" std::int32_t elisa_showcase_skia_resource_generation_before();
extern "C" std::int32_t elisa_showcase_skia_resource_generation_after();

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

bool expect_ink(const SkPixmap& pixels, SkColor background,
                int left, int top, int right, int bottom, const char* label) {
    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            if (pixels.getColor(x, y) != background) return true;
        }
    }
    std::fprintf(stderr, "%s: no rasterized glyphs in the expected region\n", label);
    return false;
}

bool expect_color(const SkPixmap& pixels, int x, int y, SkColor expected,
                  const char* label) {
    const SkColor actual = pixels.getColor(x, y);
    if (actual == expected) return true;
    std::fprintf(stderr, "%s: expected 0x%08x, got 0x%08x\n", label, expected, actual);
    return false;
}

// Hash logical pixels rather than raw row bytes. Skia may pad rows, and those
// padding bytes are not part of the rendered frame contract. The digest is
// used to prove that repeated retained/deferred replays are deterministic and
// do not accumulate transforms, clips, or stale resource state.
std::uint64_t pixel_digest(const SkPixmap& pixels) {
    std::uint64_t hash = UINT64_C(1469598103934665603);
    for (int y = 0; y < pixels.height(); ++y) {
        for (int x = 0; x < pixels.width(); ++x) {
            hash ^= static_cast<std::uint32_t>(pixels.getColor(x, y));
            hash *= UINT64_C(1099511628211);
        }
    }
    return hash;
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
    // Supply a deterministic host-decoded image while keeping the logical
    // resource lifecycle and generation replacement in Elisa. The snapshot
    // remains alive for every replay, matching a real host's borrowed image
    // contract without adding an image registry to this fixture.
    const SkImageInfo resource_info = SkImageInfo::Make(
        180, 48, kRGBA_8888_SkColorType, kPremul_SkAlphaType);
    sk_sp<SkSurface> resource_surface = SkSurfaces::Raster(resource_info);
    if (!resource_surface) {
        std::fprintf(stderr, "skia showcase: failed to create resource surface\n");
        return 5;
    }
    resource_surface->getCanvas()->clear(SkColorSetARGB(255, 44, 176, 132));
    const sk_sp<SkImage> resource_image = resource_surface->makeImageSnapshot();
    if (!resource_image || elisa_showcase_skia_bind_resource_image(
            reinterpret_cast<std::size_t>(resource_image.get())) != 1) {
        std::fprintf(stderr, "skia showcase: failed to bind the decoded resource image\n");
        return 6;
    }
    SkCanvas* canvas = surface->getCanvas();
    const std::size_t canvas_handle = reinterpret_cast<std::size_t>(canvas);
    const std::size_t font_handle = reinterpret_cast<std::size_t>(typeface.get());
    const std::int32_t status = elisa_showcase_skia_render(canvas_handle, font_handle);
    if (status != 1) {
        std::fprintf(stderr, "skia showcase: Elisa returned status %d\n", status);
        return 7;
    }

    const std::int32_t commands = elisa_showcase_skia_command_count();
    const std::int32_t semantics = elisa_showcase_skia_semantic_count();
    const std::int32_t art = elisa_showcase_skia_art_count();
    const std::int32_t deferred = elisa_showcase_skia_deferred_count();
    const std::int32_t resource_deferred = elisa_showcase_skia_resource_probe_count();
    const std::int32_t generation_before = elisa_showcase_skia_resource_generation_before();
    const std::int32_t generation_after = elisa_showcase_skia_resource_generation_after();
    if (commands <= 20 || semantics <= 10 || art < 6 || deferred != 2 ||
        resource_deferred != 2 || generation_before <= 0 || generation_after <= generation_before) {
        std::fprintf(stderr, "skia showcase: incomplete Elisa frame commands=%d semantics=%d art=%d deferred=%d resource_deferred=%d generations=%d->%d\n",
                     commands, semantics, art, deferred, resource_deferred,
                     generation_before, generation_after);
        return 8;
    }

    SkPixmap pixels;
    if (!surface->peekPixels(&pixels)) {
        std::fprintf(stderr, "skia showcase: raster pixels unavailable\n");
        return 9;
    }
    bool ok = true;
    ok = expect_color(pixels, 0, 0, SkColorSetARGB(255, 226, 231, 241), "light-theme background") && ok;
    ok = expect_ink(pixels, SkColorSetARGB(255, 238, 241, 247),
                    36, 18, 360, 58, "showcase title text") && ok;
    const int field_x = elisa_showcase_skia_text_field_x();
    const int field_y = elisa_showcase_skia_text_field_y();
    const int field_width = elisa_showcase_skia_text_field_width();
    const int field_height = elisa_showcase_skia_text_field_height();
    if (field_x < 0 || field_y < 0 || field_width <= 16 || field_height <= 12 ||
        field_x + field_width >= width || field_y + field_height >= height) {
        std::fprintf(stderr, "skia showcase: edited text field escaped retained bounds x=%d y=%d width=%d height=%d\n",
                     field_x, field_y, field_width, field_height);
        ok = false;
    } else {
        ok = expect_ink(pixels, SkColorSetARGB(255, 250, 251, 254),
                        field_x + 8, field_y + 6,
                        field_x + field_width - 8, field_y + field_height - 6,
                        "edited text field") && ok;
    }
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

    // The old resource generation was queued before retry and must not paint
    // through its disposed/failed binding. The replacement generation is
    // queued after retry and paints the host image into the adjacent box.
    const int resource_x = elisa_showcase_skia_resource_probe_x();
    const int resource_y = elisa_showcase_skia_resource_probe_y();
    if (resource_x < 0 || resource_y < 0 || resource_x + 128 >= width || resource_y + 32 >= height) {
        std::fprintf(stderr, "skia showcase: resource probe escaped retained bounds x=%d y=%d\n",
                     resource_x, resource_y);
        ok = false;
    } else {
        ok = expect_color(pixels, resource_x + 28, resource_y + 16,
                          SkColorSetARGB(255, 49, 56, 72),
                          "stale resource generation skipped") && ok;
        ok = expect_color(pixels, resource_x + 64 + 28, resource_y + 16,
                          SkColorSetARGB(255, 44, 176, 132),
                          "replacement resource generation rendered") && ok;
    }

    const std::uint64_t initial_digest = pixel_digest(pixels);

    const int iterations = configured_iterations();
    const auto render_start = std::chrono::steady_clock::now();
    for (int index = 0; index < iterations; ++index) {
        const std::int32_t repeated = elisa_showcase_skia_render(canvas_handle, font_handle);
        if (repeated != 1) {
            std::fprintf(stderr, "skia showcase: repeated render %d returned status %d\n", index, repeated);
            return 10;
        }
    }
    const auto render_finish = std::chrono::steady_clock::now();
    const auto total_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
        render_finish - render_start).count();
    const auto average_ns = total_ns / iterations;
    if (total_ns <= 0 || average_ns <= 0) {
        std::fprintf(stderr, "skia showcase: renderer timing did not produce a positive sample\n");
        ok = false;
    }
    const std::uint64_t repeated_digest = pixel_digest(pixels);
    if (repeated_digest != initial_digest) {
        std::fprintf(stderr,
                     "skia showcase: repeated replay changed the pixel digest "
                     "(initial=%016llx repeated=%016llx)\n",
                     static_cast<unsigned long long>(initial_digest),
                     static_cast<unsigned long long>(repeated_digest));
        ok = false;
    }

    SkFILEWStream stream(output);
    SkPngEncoder::Options options;
    if (!SkPngEncoder::Encode(&stream, pixels, options) || !stream.bytesWritten()) {
        std::fprintf(stderr, "skia showcase: failed to write %s\n", output);
        return 11;
    }
    if (!ok) return 12;
    std::printf("skia showcase: rendered and verified %s renderer=cpu-raster commands=%d semantics=%d art=%d deferred=%d resource_deferred=%d generations=%d->%d accent_pixels=%zu probe_x=%d probe_y=%d resource_x=%d resource_y=%d render_iterations=%d render_total_ns=%lld render_average_ns=%lld pixel_digest=%016llx\n",
                output, commands, semantics, art, deferred, resource_deferred,
                generation_before, generation_after, accent_pixels, probe_x, probe_y,
                resource_x, resource_y, iterations,
                static_cast<long long>(total_ns), static_cast<long long>(average_ns),
                static_cast<unsigned long long>(repeated_digest));
    return 0;
}
