#pragma once

#include <cstddef>
#include <cstdint>

#include "include/core/SkSurface.h"

struct ShowcaseListBenchmarkResult {
    static constexpr int warmups = 2;
    static constexpr int repetitions = 7;
    std::uint64_t samples_ns[repetitions] = {};
    std::uint64_t tail_pixel_digest = 0;
};

bool benchmark_showcase_list(SkSurface* surface, std::size_t font, int width, int height,
                             std::uint64_t initial_digest, ShowcaseListBenchmarkResult* result);
