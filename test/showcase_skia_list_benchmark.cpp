#include "showcase_skia_list_benchmark.h"

#include <chrono>
#include <cstdio>

#include "include/core/SkCanvas.h"
#include "include/core/SkColor.h"
#include "showcase_skia_pixels.h"

extern "C" std::int32_t elisa_showcase_app_skia_render(std::size_t canvas, std::size_t font,
                                                       float width, float height, std::int32_t page,
                                                       float scale);
extern "C" std::int32_t elisa_showcase_app_skia_virtual_list_workflow();
extern "C" std::int32_t elisa_showcase_app_skia_virtual_list_reinit();

bool benchmark_showcase_list(SkSurface* surface, std::size_t font, int width, int height,
                             std::uint64_t initial_digest, ShowcaseListBenchmarkResult* result) {
    if (surface == nullptr || result == nullptr) return false;
    for (int iteration = 0; iteration < ShowcaseListBenchmarkResult::warmups +
                                         ShowcaseListBenchmarkResult::repetitions; ++iteration) {
        // Rebuild the public Lists page outside the timing window. The sample
        // measures user events plus the resulting real Skia frame, not setup.
        if (elisa_showcase_app_skia_virtual_list_reinit() != 1) {
            std::fprintf(stderr, "showcase skia: could not prepare retained Lists sample %d\n", iteration);
            return false;
        }
        const auto start = std::chrono::steady_clock::now();
        const std::int32_t workflow = elisa_showcase_app_skia_virtual_list_workflow();
        if (workflow != 1) {
            std::fprintf(stderr, "showcase skia: retained Lists workflow failed at stage %d\n", workflow);
            return false;
        }
        surface->getCanvas()->clear(SK_ColorTRANSPARENT);
        const std::int32_t rendered = elisa_showcase_app_skia_render(
            reinterpret_cast<std::size_t>(surface->getCanvas()), font,
            static_cast<float>(width), static_cast<float>(height), 0, 1.0f);
        const auto end = std::chrono::steady_clock::now();
        if (rendered != 1) {
            std::fprintf(stderr, "showcase skia: tail frame returned status %d\n", rendered);
            return false;
        }
        const auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
        if (duration <= 0) {
            std::fprintf(stderr, "showcase skia: retained Lists sample had invalid duration\n");
            return false;
        }

        // Pixel scanning is diagnostic work and deliberately follows the
        // clock. It guards against timing a successful-looking but blank pass.
        const std::uint64_t digest = showcase_pixel_region_hash(surface);
        if (digest == 0 || digest == initial_digest ||
            (result->tail_pixel_digest != 0 && digest != result->tail_pixel_digest)) {
            std::fprintf(stderr, "showcase skia: retained Lists sample %d has unexpected pixels\n", iteration);
            return false;
        }
        result->tail_pixel_digest = digest;
        if (iteration >= ShowcaseListBenchmarkResult::warmups) {
            result->samples_ns[iteration - ShowcaseListBenchmarkResult::warmups] =
                static_cast<std::uint64_t>(duration);
        }
    }
    return true;
}
